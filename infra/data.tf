# Facts the provider already knows. Log, ECR and SES ARNs are built from the
# account id and the region, and no resource in this stack exports either value.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
