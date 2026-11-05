# =============================================================================
# Two Lambdas, one job each:
#   dispatcher -> turns a schedule tick into an ECS RunTask call   (3.7 sends it)
#   notifier   -> turns an S3 object arrival into an email         (3.8 sends it)
#
# Both handlers are stubs: they log the event and return. 3.6 is about the
# plumbing around them -- packaging, size, timeout, logging and, above all,
# who is allowed to invoke them. The work itself belongs to the container.
# =============================================================================

# The zip root becomes /var/task inside the function, so "handlers" must be a
# directory at the top: handler = "handlers.dispatcher.handler".
data "archive_file" "handlers" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/../.build/handlers.zip"
}

# One group per function. Lambda creates "/aws/lambda/<name>" on the first
# invocation if it is missing -- with no retention, i.e. forever. Creating it
# here, and having the function depend on it, is what keeps two weeks.
