# noc-in-a-box

A small AWS platform built to be **monitored, broken and operated like a NOC**:
Terraform-managed infrastructure, Datadog dashboards/monitors, runbooks, SLAs,
incident templates and a self-service KB. Learning/portfolio project.

## Architecture (Day 1)

```
GitHub Actions --OIDC--> AWS
                          |
Internet -> ALB (80) -> ECS Fargate service (8080) -> CloudWatch Logs
                          ^
                     ECR image (git SHA tag)
```

Design decisions (be ready to explain these):
- **Public subnets, no NAT gateway** in dev: saves ~$32/month; tasks only accept
  traffic from the ALB security group. Production would use private subnets + NAT/VPC endpoints.
- **OIDC for CI**, no long-lived AWS keys.
- **Immutable image tags (git SHA)** so every deploy is traceable and rollbacks are exact.
- **ECS deployment circuit breaker with rollback** so a bad deploy self-heals.
- **Remote state in S3 with native locking**, versioned and encrypted.

## Layout

```
bootstrap/        one-time: state bucket + GitHub OIDC role
modules/network   VPC, public subnets, routing
modules/ecs-service  cluster, task def, ALB, SGs, IAM, logs
envs/dev          wires modules together
app/              tiny JSON-logging service (/ /health /fail)
.github/workflows plan on PR, apply + smoke test on main
docs/             runbooks, SLAs, incident templates (Days 5-6)
```

## One-time setup

1. Bootstrap state + OIDC (local credentials, once):
   ```
   cd bootstrap
   terraform init
   terraform apply -var="state_bucket_name=<globally-unique-name>"
   ```
2. In the GitHub repo settings, add **Actions variables**:
   - `AWS_DEPLOY_ROLE_ARN` = output `github_deploy_role_arn`
   - `TF_STATE_BUCKET` = output `state_bucket`
3. Push to `main`. The workflow applies the ECR repo first, builds and pushes
   the image, then applies the rest and smoke-tests `/health`.

## Cost control

Dev is cheap but not free (ALB ~$16/month if left running). After each session:
```
cd envs/dev
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=eu-central-1"
terraform destroy -var="image_tag=x"
```

## Known shortcuts (to harden)

- Deploy role has `AdministratorAccess` (sandbox account). Replace with a scoped policy.
- HTTP only on the ALB. Add ACM + HTTPS when a domain is attached.
