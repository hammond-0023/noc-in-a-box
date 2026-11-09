locals {
  name  = "noc-dev"
  image = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
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

# ---------- API (behind the ALB) ----------
module "api" {
  source = "../../modules/ecs-service"

  name              = local.name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  image             = local.image
  desired_count     = var.desired_count

  environment = {
    APP_ENV            = "dev"
    QUEUE_URL          = aws_sqs_queue.orders.url
    TABLE_NAME         = aws_dynamodb_table.orders.name
    AWS_DEFAULT_REGION = var.region
  }
}

# ---------- Worker (no load balancer) ----------
module "worker" {
  source = "../../modules/worker-service"

  name               = "${local.name}-worker"
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  cluster_arn        = module.api.cluster_arn
  execution_role_arn = module.api.execution_role_arn
  image              = local.image
  command            = ["python", "worker.py"]
  desired_count      = var.worker_desired_count

  environment = {
    APP_ENV            = "dev"
    QUEUE_URL          = aws_sqs_queue.orders.url
    TABLE_NAME         = aws_dynamodb_table.orders.name
    AWS_DEFAULT_REGION = var.region
    PROCESS_SECONDS    = "2"
  }
}

# ---------- Least-privilege permissions ----------
data "aws_iam_policy_document" "api_access" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.orders.arn]
  }
  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.orders.arn]
  }
}

resource "aws_iam_role_policy" "api_access" {
  name   = "orders-access"
  role   = module.api.task_role_name
  policy = data.aws_iam_policy_document.api_access.json
}

data "aws_iam_policy_document" "worker_access" {
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.orders.arn]
  }
  statement {
    actions   = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.orders.arn]
  }
}

resource "aws_iam_role_policy" "worker_access" {
  name   = "orders-access"
  role   = module.worker.task_role_name
  policy = data.aws_iam_policy_document.worker_access.json
}
