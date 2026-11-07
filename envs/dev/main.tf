locals {
  name = "noc-dev"
}

module "network" {
  source = "../../modules/network"
  name   = local.name
}

resource "aws_ecr_repository" "app" {
  name                 = "${local.name}-app"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # dev only, so `terraform destroy` works

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

module "api" {
  source = "../../modules/ecs-service"

  name              = local.name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  image             = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
  desired_count     = var.desired_count

  environment = {
    APP_ENV = "dev"
  }
}
