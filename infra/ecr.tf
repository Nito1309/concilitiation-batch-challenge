# Container image registry for the batch job. Tags are commit SHAs, never
# `latest`: an immutable tag means a re-push of the same SHA fails instead of
# silently replacing the image a running task definition points at.
resource "aws_ecr_repository" "app" {
  name                 = "${local.name_prefix}-app"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.environment == "lab"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Cost decision: untagged layers are what pile up — each build moves a tag and
# orphans the previous manifest. Expire untagged after 1 day, keep the last 10
# tagged so a rollback has room.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the last 10 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}
