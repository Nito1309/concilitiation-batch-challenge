# Verification log

Evidence for every piece of `PLAN.md`. A piece is only done when the command in this file
has been run and its output reproduced. Commands are copy-pasteable from the repository root
unless stated otherwise.

Floci is an emulator: everything below proves the Terraform is applied and the API surface
behaves as expected, not that AWS itself behaves this way. The gaps are listed per piece and
summarised in [What Floci does not emulate](#what-floci-does-not-emulate).

## Environment

| Item | Value |
|---|---|
| Date | 2026-11-04 |
| Terraform | 1.16.7 |
| `hashicorp/aws` provider | 6.70.0 (`~> 6.70.0`) |
| `hashicorp/random` provider | 3.9.1 |
| Emulator | `floci/floci:2.3.0` (`docker-compose.yml`) |
| Endpoint from the host shell | `http://localhost:4566` |
| Endpoint from another container | `http://host.docker.internal:4566` |

`floci` only resolves inside the Compose network, so `localhost:4566` is correct on the host
and wrong from a sibling container. The platform values in `infra/terraform.tfvars` come from
`terraform -chdir=bootstrap-floci output -json`.

---

## 3.3 — Container image repository (`infra/ecr.tf`)

### Apply

```bash
cd infra
terraform init
terraform fmt -check -recursive
terraform validate
terraform apply
```

```text
Success! The configuration is valid.

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

repository_url = "<registry>/conciliacion-batch-lab-app"
s3_bucket_name = "conciliacion-batch-lab-b996ee"
```

Two resources are added, and both are intended: `aws_ecr_repository.app` and
`aws_ecr_lifecycle_policy.app`. The policy is a separate resource in the AWS provider, not an
inline block, so "create the repository" is two resources on a clean state. No resource is
replaced or destroyed.

### Tag immutability and scanning

```bash
aws --endpoint-url http://localhost:4566 ecr describe-repositories \
  --repository-names conciliacion-batch-lab-app \
  --query 'repositories[0].{tag:imageTagMutability,scan:imageScanningConfiguration.scanOnPush}' \
  --output json
```

```json
{ "tag": "IMMUTABLE", "scan": true }
```

`IMMUTABLE` is the decision, not a default: CI tags images with the commit SHA, so a tag must
identify exactly one image. Re-pushing an existing tag fails with
`ImageTagAlreadyExistsException` instead of silently moving the tag to different bits, which
would break rollback and the commit-to-image audit trail. A rebuild of the same commit gets a
new tag (`<sha>-2`), never a recycled one.

`scan_on_push` records a scan request on every push. The scan does not block the push, so a
CI job that wants to fail on findings must poll `describe-image-scan-findings` afterwards.

### Retention policy

```bash
aws --endpoint-url http://localhost:4566 ecr get-lifecycle-policy \
  --repository-name conciliacion-batch-lab-app \
  --query lifecyclePolicyText --output text
```

```json
{"rules":[
 {"action":{"type":"expire"},"description":"Expire untagged images after 1 day","rulePriority":1,
  "selection":{"countNumber":1,"countType":"sinceImagePushed","countUnit":"days","tagStatus":"untagged"}},
 {"action":{"type":"expire"},"description":"Keep the last 10 tagged images","rulePriority":2,
  "selection":{"countNumber":10,"countType":"imageCountMoreThan","tagPatternList":["*"],"tagStatus":"tagged"}}]}
```

How the two rules interact: rules are evaluated in priority order and the first match wins, so
an image is never counted twice. Rule 1 removes untagged manifests older than one day — those
are the ones that grow storage, since deleting or moving a tag leaves the manifest behind.
Rule 2 then keeps the ten most recently pushed tagged images and expires the rest, which is
the rollback window.

Two properties worth knowing:

- `sinceImagePushed` measures age from the push, not from the moment an image lost its tag. An
  image pushed a month ago and untagged today is eligible on the next run; the "1 day" is not a
  grace period after untagging.
- `tagPatternList: ["*"]` counts *every* tag, including a release tag if one is added later.
  If promotion tags (`v1.2.3`) are introduced, they must be excluded by pattern
  (for example `["sha-*"]`) or they can be expired by rule 2.

`force_delete = var.environment == "lab"` exists so `terraform destroy` works on a repository
holding images locally, and is false in any other environment.

### Reproduce from a clean clone

```bash
git clone <repo> && cd conciliacion-batch-challenge
cp infra/terraform.tfvars.example infra/terraform.tfvars   # fill the 5 platform values
docker compose up -d floci
terraform -chdir=infra init && terraform -chdir=infra apply
# then run the two aws commands above
```

`terraform init` on a platform whose provider hashes are not in
`infra/.terraform.lock.hcl` fails with `missing or corrupted provider plugins`. The lock file
pins `darwin_arm64`, `linux_amd64` and `linux_arm64`; adding another platform is
`terraform providers lock -platform=<os>_<arch>` and committing the result.

### What this does not prove

- **Tag immutability is not exercised end to end.** Floci answers `PutImage` with
  `UnsupportedOperation`, so the overwrite rejection was not observed against this emulator;
  `describe-repositories` proves the setting is stored, not that the registry enforces it.
  Against a real registry the check is a second `docker push` of the same tag, expected to fail
  with `ImageTagAlreadyExistsException`.
- **No image was pushed**, so the retention rules have never had a subject to act on.
- **Scanning produced no findings** — `scanOnPush` is configuration; nothing scans locally.

---

## 3.4 — IAM roles and policies (`infra/iam.tf`)

### Apply

```bash
cd infra
terraform fmt -check -recursive
terraform validate
terraform apply
```

```text
Success! The configuration is valid.

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

The five are `aws_iam_role.task`, `aws_iam_role.dispatcher`,
`aws_iam_role_policy.task_exec_secret`, `aws_iam_role_policy.dispatcher` and
`aws_iam_role_policy_attachment.dispatcher_logs`; the execution role and its first two policies
came from the previous apply. A second `terraform plan` reports no changes, and the
`aws_iam_policy_document` blocks add nothing to count: they render JSON locally and that JSON is
stored on the policy referencing them.

### Four roles, one per identity

| Role | Assumed by | Granted |
| --- | --- | --- |
| `conciliacion-batch-lab-task-exec` | ECS agent, before the container starts | pull the image, write log streams, read the DB secret |
| `conciliacion-batch-lab-task` | the app code inside the container | `s3:GetObject`/`PutObject` on the bucket objects, `s3:ListBucket` |
| `conciliacion-batch-lab-dispatcher` | Lambda | `ecs:RunTask` on the app task definition, `iam:PassRole` for the task role only |
| `conciliacion-batch-lab-notifier` | Lambda | `ses:SendEmail` as the verified sender identity |

### Which policy sits on which role

```bash
for r in task-exec task dispatcher notifier; do
  echo "-- $r"
  aws --endpoint-url http://localhost:4566 iam list-role-policies \
    --role-name conciliacion-batch-lab-$r --query PolicyNames --output text
  aws --endpoint-url http://localhost:4566 iam list-attached-role-policies \
    --role-name conciliacion-batch-lab-$r --query 'AttachedPolicies[].PolicyName' --output text
done
```

```text
-- task-exec
task-exec-logs	task-exec-ecr	task-exec-secret
-- task
task-s3
-- dispatcher
dispatcher-ecs
AWSLambdaBasicExecutionRole
-- notifier
notifier-ses
AWSLambdaBasicExecutionRole
```

Inline policies are named `<role>-<concern>` so a single `get-role-policy` answers "what may this
role do", one concern at a time. The two managed attachments are the same AWS policy: Lambda log
permissions are not worth hand-writing.

### Least privilege check

```bash
for r in task-exec task dispatcher notifier; do
  for p in $(aws --endpoint-url http://localhost:4566 iam list-role-policies \
      --role-name conciliacion-batch-lab-$r --query PolicyNames --output text); do
    aws --endpoint-url http://localhost:4566 iam get-role-policy \
      --role-name conciliacion-batch-lab-$r --policy-name "$p" \
      --query PolicyDocument --output json
  done
done | grep -c '"Resource": "\*"'
```

```text
1
```

One wildcard across the six inline policies: `ecr:GetAuthorizationToken`, which issues a registry
token for the whole account and has no ARN form. Every other statement names exactly one
repository, log group, secret, bucket, task definition or SES identity.

### What this does not prove

- **Nothing here is enforced.** Floci stores policies and accepts the API calls that follow, so a
  misspelled action, a policy on the wrong role and a missing permission all read back fine. The
  commands above prove shape, not authorization.
- **No role has ever been assumed.** Nothing in the stack calls `sts:AssumeRole` yet: there is no
  running task (3.5) and no deployed Lambda (3.8), so the trust policies are configuration only.
- **The `iam:PassRole` condition is untested.** `iam:PassedToService` is evaluated when a service
  hands a role to another service, which no local command does.

---

## 3.5 — ECS cluster and the RunTask task definition (`infra/ecs.tf`)

The piece adds no service. The job exists to run once, so the proof is a `RunTask` call that
starts a container, the agent resolves the database secret, the app writes its JSON events to
CloudWatch, and the task stops with a reason.

### Apply

```bash
cd infra
terraform fmt -check -recursive
terraform validate
terraform apply
```

```text
Apply complete!

cluster_name      = "conciliacion-batch-lab"
repository_url    = "000000000000.dkr.ecr.us-east-1.localhost:4566/conciliacion-batch-lab-app"
s3_bucket_name    = "conciliacion-batch-lab-b996ee"
task_definition_arn = "arn:aws:ecs:us-east-1:000000000000:task-definition/conciliacion-batch-lab-app:1"
```

Four resources are new: the log group, the task security group, the cluster and the task
definition. Nothing else changes shape — the log group rename in this piece only alters a string
inside the execution role's policy, which Terraform rewrites in place.

The cluster name is `<project>-<environment>`, which is `local.name_prefix`: the same prefix the
role names, the bucket and the repository already use.

### Image

The task definition pins `var.image_tag` on `aws_ecr_repository.app.repository_url`. Before the
first run the registry has to hold that tag:

```bash
REGISTRY=$(terraform -chdir=infra output -raw repository_url)
docker build -t "${REGISTRY}:local" app/
aws --endpoint-url http://localhost:4566 ecr get-login-password \
  | docker login --username AWS --password-stdin "${REGISTRY%%/*}"
docker push "${REGISTRY}:local"
```

```text
local: digest: sha256:519211abf015af686e9d07ff482a4e4dddf6460fc3652caba9cf85b57a34c942 size: 2497
```

### One run

```bash
aws --endpoint-url http://localhost:4566 ecs run-task \
  --cluster conciliacion-batch-lab \
  --task-definition conciliacion-batch-lab-app \
  --launch-type FARGATE \
  --network-configuration 'awsvpcConfiguration={subnets=[subnet-8409913d,subnet-dd772813],securityGroups=[sg-6e8d5db7b3fbafa35],assignPublicIp=DISABLED}' \
  --query 'tasks[0].taskArn' --output text
```

Cluster and task definition come from `terraform -chdir=infra output`; the subnets are
`var.subnet_ids` from `infra/terraform.tfvars` and the security group is
`terraform output -raw task_security_group_id`. They are written out here because a task
definition cannot carry them: a `RunTask` call has to supply the network every time.

```bash
aws --endpoint-url http://localhost:4566 ecs describe-tasks \
  --cluster conciliacion-batch-lab \
  --tasks "arn:aws:ecs:us-east-1:000000000000:task/conciliacion-batch-lab/86992a269169468b91aaa18b93c8e08d" \
  --query 'tasks[0].{last:lastStatus,desired:desiredStatus,reason:stoppedReason,exit:containers[0].exitCode}'
```

```text
{"last": "RUNNING", "desired": "RUNNING", "reason": null, "exit": null}
{"last": "STOPPED", "desired": "STOPPED", "reason": "Essential container in task exited", "exit": 2}
```

`assignPublicIp=DISABLED` matches the private subnets the platform bootstrap creates: the task
reaches the internet through the NAT gateway, never through an address of its own.

Exit code 2 is the app refusing to start: the definition supplies `RUN_MODE`/`BUCKET_NAME` and the
database credentials, but `daily` also needs `PROVIDER_API_KEY`, which arrives per run once 3.7
wires the scheduler. The definition is correct; the job is simply not fully parameterised yet.

The logs of that run:

```bash
aws --endpoint-url http://localhost:4566 logs get-log-events \
  --log-group-name /ecs/conciliacion-batch-lab-app \
  --log-stream-name app/app/86992a269169468b91aaa18b93c8e08d \
  --query 'events[].message' --output text
```

The group is `/ecs/<local.name_prefix>-app` and the stream is `<awslogs-stream-prefix>/<container>/<task id>`,
which is why the prefix has to be a plain `app`: it becomes part of every path.

```text
{"timestamp": "2026-11-05T18:31:00.435+00:00", "level": "INFO", "message": "Inicio de la ejecución", "run_id": "750b2dd7-635d-4d47-ab6f-b16d2da9ef3c"}
{"timestamp": "2026-11-05T18:31:00.436+00:00", "level": "ERROR", "message": "Falta la variable de entorno requerida PROVIDER_API_KEY", "run_id": "750b2dd7-635d-4d47-ab6f-b16d2da9ef3c", "tipo": "ErrorConfiguracion", "codigo_salida": 2}
```

Two events are enough to prove the log path end to end: the app's own structured line (not just a
crash trace) landed in the group the execution role was granted, in a stream prefixed `app`.

### The secret reaches the container

Exit code 2 stops the run before the database is touched, so the `secrets` block needs its own
check. The run below overrides the container command and prints what the agent resolved, never
the password itself:

```bash
cat > /tmp/ov.json <<'JSON'
{
  "containerOverrides": [
    {
      "name": "app",
      "command": [
        "python", "-c",
        "import os;print('RESOLVED', os.environ['DB_HOST'], os.environ['DB_PORT'], os.environ['DB_NAME'], os.environ['DB_USER'], 'pw_chars=%d' % len(os.environ['DB_PASSWORD']))"
      ]
    }
  ]
}
JSON

aws --endpoint-url http://localhost:4566 ecs run-task \
  --cluster conciliacion-batch-lab \
  --task-definition conciliacion-batch-lab-app \
  --launch-type FARGATE \
  --network-configuration 'awsvpcConfiguration={subnets=[subnet-8409913d],securityGroups=[sg-6e8d5db7b3fbafa35],assignPublicIp=DISABLED}' \
  --overrides file:///tmp/ov.json
```

```text
RESOLVED floci 7001 conciliacion conciliacion_admin pw_chars=24
```

Every value matches the secret JSON (`host`, `port`, `dbname`, `username`, and a 24-character
password), which is the point of `valueFrom = "${var.db_secret_arn}:<key>::"`: the mapping between
the secret's key names and the app's variable names is correct, and the password never appears in
the task definition or in this file.

### What this does not prove

- **Security group rules are not enforced.** Floci has no packet filter: the task reaches the
  database because the emulator does not route traffic at all. The two egress rules are a
  statement of intent that only a real VPC verifies.
- **The task group never converges.** Floci keeps the allow-all egress rule that AWS adds to every
  new group and does not honour the provider's attempt to revoke it, so `terraform plan` reports
  one in-place update on `aws_security_group.task` right after a clean apply. On real AWS the same
  configuration plans clean; re-applying here changes nothing and the diff returns.
- **The task is not listed once it stops.** `list-tasks` returns running tasks only, so the
  `describe-tasks` call has to keep the ARN returned by `run-task` and run while the task still
  exists. An empty `list-tasks` right after a run is not a failure.
- **The job itself has not run.** Exit code 2 is a configuration error reached before any database
  or S3 call: nothing here proves the reconciliation logic, the S3 policy on the task role, or the
  database credentials beyond their shape.
- **Nothing schedules yet.** There is no service, no EventBridge rule and no dispatcher Lambda, so
  the subnets, the security group and `assignPublicIp` in this section are still typed by hand.
  3.6 hands the same three values to the dispatcher Lambda as environment variables, but the
  `RunTask` call itself lands in Piece 4.

---

## 3.6 — Dispatcher and notifier Lambdas (`infra/lambda.tf`)

Two functions, one job each, and both handlers are stubs that only log. The proof for this piece
is therefore not "the batch ran" but "the trigger reaches the function": a direct invoke of the
dispatcher, and an `inbox/` upload that reaches the notifier with nobody calling it.

### Apply

```bash
cd infra
terraform fmt -check -recursive
terraform validate
terraform apply
```

```text
Apply complete! Resources: 7 added, 1 changed, 0 destroyed.

dispatcher_function_name = "conciliacion-batch-lab-dispatcher"
notifier_function_name   = "conciliacion-batch-lab-notifier"
```

Seven is the whole surface: two log groups, two functions, two invoke permissions and one bucket
notification. The single change belongs to 3.5 — it is the leftover allow-all egress rule in
`aws_security_group.task` being brought back to what the configuration says, and it is why the
plan now reports `No changes`.

A later apply can still show two in-place updates on the functions, with an unchanged handler
and a new `source_code_hash`. `archive_file` hashes the zip, and a zip stores each file's
modification time, so rewriting a handler with identical bytes produces a different hash and a
deployment that changes nothing. The hash is trying to express "the code changed"; a timestamp
leaks into it. Keeping the unzipped source stable between applies is what keeps the plan quiet.

### One invoke

The dispatcher's input in production is a scheduler tick, so the test payload is that shape:

```bash
cat > sched_event.json <<'EOF'
{"version":"0","id":"b7c1f0aa-6f2e-4a52-9d1f-2f0f7c7a4b1e","source":"aws.scheduler",
 "account":"000000000000","time":"2026-11-05T12:00:00Z","region":"us-east-1",
 "detail-type":"Scheduled Event","detail":{"scheduledTime":"2026-11-05T12:00:00Z"}}
EOF

aws --endpoint-url http://localhost:4566 lambda invoke \
  --function-name conciliacion-batch-lab-dispatcher \
  --cli-binary-format raw-in-base64-out \
  --payload file://sched_event.json /tmp/dispatcher_out.json

cat /tmp/dispatcher_out.json
```

```text
{"ok": true, "procesado": false, "motivo": "stub de 3.6"}
```

`--cli-binary-format raw-in-base64-out` is not optional: aws-cli v2 base64-encodes `--payload`
by default, and the API rejects a JSON body it cannot decode (`Invalid base64: "{"version":"0"…`).
With the flag the file is sent byte for byte, which is what a scheduler would send.

### The event lands in the log

```bash
aws --endpoint-url http://localhost:4566 logs describe-log-streams \
  --log-group-name /aws/lambda/conciliacion-batch-lab-dispatcher
```

```text
2026/11/05/[$LATEST]336602ab
```

```bash
aws --endpoint-url http://localhost:4566 logs get-log-events \
  --log-group-name /aws/lambda/conciliacion-batch-lab-dispatcher \
  --log-stream-name '2026/11/05/[$LATEST]336602ab' --query 'events[].message' --output text
```

```text
[INFO]  Evento recibido: {"version": "0", "id": "b7c1f0aa-…", "source": "aws.scheduler", …}
[INFO]  Destino: cluster=conciliacion-batch-lab task_definition=conciliacion-batch-lab-app
        subnets=subnet-8409913d,subnet-dd772813 security_groups=sg-6e8d5db7b3fbafa35
```

The second line is the real check. It shows that the four environment variables reach the
function and already hold the values `RunTask` needs — the same cluster, family, subnets and
group that were typed by hand in 3.5. Nothing reads them yet; that is Piece 4.

The stream name has a fixed shape, `YYYY/MM/DD/[version]<suffix>`: one stream per execution
environment, and `$LATEST` because the function has no published version or alias. The group is
`/aws/lambda/<function name>`, the name Lambda would have created on the first invocation — with
no retention on it. The group exists before the function on purpose, so the function inherits it
instead of creating an immortal one.

### The bucket calls the notifier

Two uploads, one per prefix, so the filter is tested in both directions:

```bash
aws --endpoint-url http://localhost:4566 s3api put-object \
  --bucket conciliacion-batch-lab-b996ee \
  --key data/2026-11-05/resultado.json --body entrada_prueba.csv

aws --endpoint-url http://localhost:4566 s3api put-object \
  --bucket conciliacion-batch-lab-b996ee \
  --key inbox/entrada_prueba.csv --body entrada_prueba.csv

aws --endpoint-url http://localhost:4566 logs describe-log-streams \
  --log-group-name /aws/lambda/conciliacion-batch-lab-notifier
```

```text
2026/11/05/[$LATEST]663c91e9
```

One stream, not two: the `data/` write produced no invocation at all, which is the point of
`filter_prefix = local.s3_prefixes.inbox`. The app writes to `data/` and `reports/` on every run,
and only `inbox/` is a human asking for an email.

```bash
aws --endpoint-url http://localhost:4566 logs get-log-events \
  --log-group-name /aws/lambda/conciliacion-batch-lab-notifier \
  --log-stream-name '2026/11/05/[$LATEST]663c91e9' --query 'events[].message' --output text
```

```text
[INFO]  Evento recibido: {"Records": [{"eventSource": "aws:s3", "eventName": "ObjectCreated:Put",
        "s3": {"bucket": {"name": "conciliacion-batch-lab-b996ee"},
               "object": {"key": "inbox/entrada_prueba.csv", "size": 25}}}]}
[INFO]  Correo: de=notifications@example.com para=sre@example.com
```

No one called the notifier: S3 did, asynchronously, because the bucket notification says so and
because the function's policy allows this bucket to. `SES_SENDER` and `SES_RECIPIENT` are read
from the environment, so 3.8 only has to replace the log line with a `send_email` call.

### Who may invoke

```bash
aws --endpoint-url http://localhost:4566 lambda get-policy \
  --function-name conciliacion-batch-lab-dispatcher --query Policy --output text
```

```json
{"Statement": [{"Sid": "AllowSchedulerInvoke", "Effect": "Allow",
  "Principal": {"Service": "scheduler.amazonaws.com"},
  "Action": "lambda:InvokeFunction",
  "Resource": "arn:aws:lambda:us-east-1:000000000000:function:conciliacion-batch-lab-dispatcher",
  "Condition": {"ArnLike": {"AWS:SourceArn":
    "arn:aws:scheduler:us-east-1:000000000000:schedule/default/conciliacion-batch-lab-daily"}}}]}
```

The condition is the interesting half. Without `source_arn`, every schedule in every account that
learns the function name could start tasks; with it, exactly one schedule can. That ARN does not
exist yet — 3.7 creates it — so the name lives in `local.dispatch_schedule_name`, and the schedule
must be created with it or the invoke is denied.

The S3 permission is the mirror image: `principal = s3.amazonaws.com`, `source_arn` of this
bucket, and `source_account`, which closes the gap `source_arn` alone leaves (a bucket in another
account can carry the same name in its own ARN shape).

### Why the notification has `depends_on`

S3 checks the destination when the notification is written: it reads the function's policy to
confirm that `s3.amazonaws.com` may invoke it. If the permission resource is still pending, the
bucket rejects the entire configuration with *Unable to validate destination configuration* —
a failure whose message points at the notification, not at the missing permission. The
`depends_on` is the difference between a first apply that works and one that does not.

### What this does not prove

- **Nothing calls ECS.** The dispatcher returns after logging; `RunTask` is Piece 4. The four
  environment variables are proven to arrive, not to be used.
- **No mail leaves the account.** The notifier logs sender and recipient; SES identities, the
  send permission and the template are 3.8.
- **The scheduler does not exist.** The permission names an ARN that only 3.7 will create, so the
  end-to-end path "schedule fires → dispatcher runs" cannot be observed yet.
- **The zip carries code, not dependencies.** `archive_file` zips `lambda/` as it is: no
  `boto3` pin, no layer, no `requirements.txt`. Piece 4 adds whatever the handlers import.
- **Floci does not enforce IAM.** Every invoke here would succeed with an empty role policy, so
  the policies are shape, not permission. The two `aws_lambda_permission` resources are stored and
  readable, but nothing in the emulator tests a denied cross-account call.
- **The notification is emulator-flavoured.** The delivered record carries
  `"configurationId": "emulator"` instead of the `inbox-to-notifier` id from the configuration,
  and `"userIdentity": {"principalId": "AWS:EMULATOR"}`. The filter and the target are real; those
  two fields are not.

## 3.7 — the daily schedule (`infra/scheduler.tf`)

Five resources to make one function run at 05:00: the schedule itself, the role Scheduler assumes to
call it, that role's permission, a queue for invocations that never succeed, and the queue's
permission. The schedule is one block; the rest is what makes a failed tick visible instead of
silent.

### Apply

```console
$ terraform -chdir=infra apply
...
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

```console
$ aws --endpoint-url http://localhost:4566 scheduler get-schedule \
    --name conciliacion-batch-lab-daily --group-name default
{
    "Arn": "arn:aws:scheduler:us-east-1:000000000000:schedule/default/conciliacion-batch-lab-daily",
    "Description": "Daily reconciliation run at 05:00 America/Mexico_City.",
    "FlexibleTimeWindow": { "Mode": "OFF" },
    "GroupName": "default",
    "Name": "conciliacion-batch-lab-daily",
    "ScheduleExpression": "cron(0 5 * * ? *)",
    "ScheduleExpressionTimezone": "America/Mexico_City",
    "State": "ENABLED",
    "Target": {
        "Arn": "arn:aws:lambda:us-east-1:000000000000:function:conciliacion-batch-lab-dispatcher",
        "DeadLetterConfig": { "Arn": "arn:aws:sqs:us-east-1:000000000000:***" },
        "RetryPolicy": { "MaximumEventAgeInSeconds": 3600, "MaximumRetryAttempts": 3 },
        "RoleArn": "arn:aws:iam::000000000000:role/conciliacion-batch-lab-scheduler"
    }
}
```

`State` is `ENABLED` from creation: a schedule that has to be switched on afterwards is a schedule
someone forgets to switch on. `GroupName` is `default` because 3.6 pinned the invoke permission to
`.../schedule/default/<name>` — the group is part of that ARN, not a label.

### The timezone is the whole point

```console
$ TZ=America/Mexico_City date '+%Y-%m-%d %H:%M %Z (UTC%z)'
2026-11-05 15:05 CST (UTC-0600)
$ TZ=UTC date '+%Y-%m-%d %H:%M %Z'
2026-11-05 21:05 UTC
```

05:00 in Mexico City is 11:00 UTC today. In summer the same city is `CDT` (UTC-5) and 05:00 local
becomes 10:00 UTC. `cron(0 11 * * ? *)` would therefore be right for half the year and one hour late
for the other half; `cron(0 5 * * ? *)` with `schedule_expression_timezone` is right every day,
because Scheduler resolves the zone per run and the expression never changes.

This is also the reason this is an `aws_scheduler_schedule` and not an `aws_cloudwatch_event_rule`: a
rule's cron is read in UTC and it publishes to a bus for someone else to route, while a schedule
keeps its own zone, its own retry budget and its own role.

### Two permissions pointing at each other

```console
$ aws iam get-role-policy --role-name conciliacion-batch-lab-scheduler \
    --policy-name scheduler-invoke --query PolicyDocument
{
  "Statement": [{
    "Sid": "InvokeDispatcher",
    "Action": "lambda:InvokeFunction",
    "Resource": "arn:aws:lambda:...:function:conciliacion-batch-lab-dispatcher",
    "Condition": { "ArnLike": { "aws:SourceArn": "arn:aws:scheduler:...:schedule/default/conciliacion-batch-lab-daily" } }
  }]
}
```

3.6's `aws_lambda_permission` allows `scheduler.amazonaws.com` on one schedule ARN; this policy
allows one function, and only when the caller is that same schedule ARN. Either side alone is too
broad, and the string they agree on is `local.dispatch_schedule_name` — the one thing to check first
if an invoke is ever denied.

The ARN is written out here instead of referenced from `aws_scheduler_schedule.daily.arn` because
the schedule's target points back at this role: referencing it would be a cycle. Both sides derive
from the same local, which is what keeps the copy honest.

### The retry budget

AWS retries a failed schedule target 185 times over 24 hours by default. For a job that runs daily,
that means a broken invocation from yesterday is still being retried when today's run is due, and
the DLQ fills behind both. Three attempts inside one hour ends the argument before the next run
starts; whatever still fails lands in `conciliacion-batch-lab-scheduler-dlq`, which keeps messages
for 14 days — the same window as the log groups, so a failure and its logs expire together.

### Nothing ticks here

Floci stores a schedule and returns it faithfully, but it does not run a timer. Probed with a
throwaway `rate(1 minute)` schedule and nothing else:

```console
$ aws ... scheduler create-schedule --name probe-rate --schedule-expression "rate(1 minute)" ...
streams before: 3
streams after:  3        # 140 seconds later
```

Three log streams before, three after, no invocation. On AWS the same configuration produces a new
stream within a minute of the cron firing.

### What this does not prove

- **No tick.** The expression, zone and target are stored and readable; the firing is not
  reproducible in the emulator, so "runs at 05:00" is a claim about the definition only.
- **The permission was never exercised.** The loop above would need Floci to fire for the
  `SourceArn` condition to be evaluated at all, and IAM is not enforced here anyway.
- **The DLQ never received anything.** Its retention, SSE and role permission are readable; an
  exhausted retry is not producible without a failing target.
- **`list-schedules` drops fields.** It returned `None` for both `ScheduleExpression` and
  `ScheduleExpressionTimezone` while `get-schedule` had them. Read a schedule one at a time.
- **Floci masks the queue name in ARNs.** `DeadLetterConfig.Arn` comes back as
  `arn:aws:sqs:us-east-1:000000000000:***`, and `get-queue-attributes` masks `QueueArn` the same
  way, so the DLQ is identifiable by its URL, not by the ARN the API echoes.
- **The schedule name is load-bearing.** Renaming it in `locals.tf` without re-applying the Lambda
  permission leaves a schedule whose invoke is denied, and nothing in `get-schedule` shows it.

## What Floci does not emulate

Applies to this piece and grows as the other pieces land.

- Registry write path: `PutImage` returns `UnsupportedOperation`, so no push, no immutability
  rejection, no scan findings. `repository_url` also carries the emulator's placeholder
  account id (`000000000000`), so it is not a real registry host — quote it as
  `<registry>/<repo>`, never verbatim.
- Lifecycle policies are stored as text only. There is no daily evaluation job, so nothing
  expires; the policy can be read back but never observed deleting an image. AWS also exposes
  `get-lifecycle-policy-preview` to dry-run a policy, and Floci does not implement it.
- IAM: policies are accepted and stored but not enforced by the emulated services.
