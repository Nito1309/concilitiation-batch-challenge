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
