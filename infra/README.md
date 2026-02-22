# Infrastructure — NTT GCC Assignment 1

Terraform IaC for a secure AWS landing zone running a containerised microservice on ECS Fargate.
All modules follow least-privilege, encryption-at-rest, and GCC compliance principles.

---

## Directory Structure

```
infra/
├── bootstrap/          # One-time: S3 state bucket, DynamoDB lock, KMS key
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
│
├── resources/          # Main Terraform root — run terraform init/plan/apply here
│   ├── backend.tf      # S3 remote state backend
│   ├── provider.tf     # AWS provider with workspace-based role assumption
│   ├── variables.tf    # All input variables
│   ├── outputs.tf      # Stack outputs (ALB DNS, ECS cluster, etc.)
│   ├── workspaces/
│   │   └── Production.tfvars   # Production environment values
│   ├── 1-networking.tf # VPC, subnets, IGW, NAT GW, route tables, NACLs, SGs
│   ├── 2-alb.tf        # S3 access logs, ACM, ALB, target group, WAF
│   ├── 3-ecs.tf        # KMS, CloudWatch logs, ECR, IAM roles, ECS cluster/task/service/ASG
│   └── 4-alarms.tf     # CloudWatch alarms (CPU/memory/5xx/errors), SNS topic
│
└── modules/            # Reusable modules (called from resources/)
    ├── acl/            # Network ACL (stateless rules)
    ├── acm/            # ACM certificate with Route53 DNS validation
    ├── alb/            # Application Load Balancer + listeners
    ├── cwalarms/       # CloudWatch Alarms + SNS topic
    ├── cwlog/          # CloudWatch Log Group (KMS-encrypted, configurable retention)
    ├── ecr/            # ECR repository (immutable tags, KMS, lifecycle policy)
    ├── ecs/            # ECS Cluster (Container Insights, ECS Exec via KMS)
    ├── ecsasg/         # ECS Application Auto Scaling (CPU + memory target tracking)
    ├── ecsservice/     # ECS Service (rolling update, circuit breaker)
    ├── ecstask/        # ECS Task Definition (Fargate, awsvpc, runtime platform)
    ├── iamrole/        # IAM Role (trust policy, managed + inline policies)
    ├── igw/            # Internet Gateway
    ├── kms/            # KMS Key (custom policy, rotation, alias)
    ├── natgw/          # NAT Gateway + Elastic IP
    ├── routetable/     # Route Table + subnet associations
    ├── s3/             # S3 bucket (versioning, encryption, lifecycle, public access block)
    ├── sg/             # Security Group (ingress/egress rules via separate rule resources)
    ├── subnet/         # Subnet (AZ, CIDR, public IP assignment)
    ├── tg/             # ALB Target Group (health check, deregistration delay)
    ├── vpc/            # VPC (DNS, default SG restriction)
    └── waf/            # WAF v2 Web ACL (IP reputation, OWASP, rate limit, logging)
```

---

## Prerequisites

| Tool | Version |
|---|---|
| Terraform | >= 1.14.0 |
| AWS Provider | 6.33.0 (pinned) |
| AWS CLI | v2 |
| tflint | latest |

---

## First-Time Setup (Bootstrap)

Bootstrap provisions the S3 state bucket, DynamoDB lock table, and KMS key.
Run this once per AWS account before the main `resources/` root.

```bash
cd infra/bootstrap

# Authenticate (use your developer profile)
export AWS_PROFILE=your-profile

terraform init
terraform plan
terraform apply
```

Bootstrap outputs the bucket name and KMS key alias used in `resources/backend.tf`.

---

## Standard Deployment

### Local Development

```bash
cd infra/resources

# Authenticate
export AWS_PROFILE=your-profile

# Initialise (downloads providers, connects to S3 backend)
terraform init

# Select workspace (auto-selects Production via TF_WORKSPACE in CI)
terraform workspace select Production
# or create it first:
terraform workspace new Production

# Plan with Production variables
terraform plan -var-file=workspaces/Production.tfvars

# Apply
terraform apply -var-file=workspaces/Production.tfvars
```

### CI/CD (GitHub Actions)

The pipeline handles all steps automatically:

- **Push / PR to `main`** → triggers `infra.yml`
- **PR** → runs validate + Checkov policy gate + posts `terraform plan` as a PR comment
- **Merge to `main`** → runs `terraform apply` automatically

Required GitHub Secrets:

| Secret | Description |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | ARN of the IAM role assumed via OIDC (e.g., `arn:aws:iam::ACCOUNT:role/GitHubActionsRole`) |

The OIDC role must have `sts:AssumeRole` permissions on the `TerraformRole` defined in `workspace_iam_roles`.

---

## Module Reference

### `vpc`
Creates the VPC with DNS hostnames/support enabled and restricts the default security group (deny all).

```hcl
module "vpc" {
  source   = "../modules/vpc"
  name     = "my-vpc"
  vpc_cidr = "10.0.0.0/16"
  tags     = var.tags
}
```

---

### `subnet`
Creates a subnet with optional public IP auto-assignment.

```hcl
module "subnet" {
  source              = "../modules/subnet"
  name                = "public-1a"
  vpc_id              = module.vpc.vpc_id
  cidr_block          = "10.0.1.0/24"
  availability_zone   = "ap-southeast-1a"
  map_public_ip       = true
  tags                = var.tags
}
```

---

### `sg`
Creates a security group with separate ingress/egress rule resources (avoids in-line rule conflicts).

```hcl
module "sg_alb" {
  source      = "../modules/sg"
  name        = "alb-sg"
  description = "ALB security group"
  vpc_id      = module.vpc.vpc_id
  ingress_rules = [
    { description = "HTTP",  from_port = 80,  to_port = 80,  protocol = "tcp",
      cidr_blocks = ["0.0.0.0/0"], security_group_id = null },
    { description = "HTTPS", from_port = 443, to_port = 443, protocol = "tcp",
      cidr_blocks = ["0.0.0.0/0"], security_group_id = null },
  ]
  egress_rules = [
    { description = "All",   from_port = 0,   to_port = 0,   protocol = "-1",
      cidr_blocks = ["0.0.0.0/0"], security_group_id = null },
  ]
  tags = var.tags
}
```

---

### `kms`
Creates a KMS CMK with a custom key policy, rotation enabled, and an alias.

```hcl
module "kms" {
  source      = "../modules/kms"
  description = "CMK for ECS logs"
  alias_name  = "alias/my-prefix-Ecs"
  key_policy  = jsonencode({ ... })
  tags        = var.tags
}
```

---

### `cwlog`
Creates a CloudWatch Log Group with KMS encryption and configurable retention.

```hcl
module "cwlog" {
  source            = "../modules/cwlog"
  name              = "/ecs/app/my-prefix"
  retention_in_days = 365      # GCC minimum: 365
  kms_key_arn       = module.kms.key_arn
  tags              = var.tags
}
```

---

### `ecr`
Creates an ECR repository with immutable tags, KMS encryption, and a lifecycle policy.

```hcl
module "ecr" {
  source           = "../modules/ecr"
  name             = "my-app"
  kms_key_arn      = module.kms.key_arn
  lifecycle_policy = jsonencode({ rules = [...] })
  tags             = var.tags
}
```

---

### `alb`
Creates an ALB with access logging, deletion protection, and HTTP/HTTPS listeners.

```hcl
module "alb" {
  source              = "../modules/alb"
  name                = "my-alb"
  subnet_ids          = module.subnets.public_subnet_ids
  security_group_ids  = [module.sg_alb.sg_id]
  certificate_arn     = module.acm.certificate_arn
  target_group_arn    = module.tg.target_group_arn
  access_logs_bucket  = module.s3_logs.bucket_id
  tags                = var.tags
}
```

---

### `waf`
Creates a WAF v2 Web ACL (REGIONAL) with managed rules and rate limiting, then associates it with an ALB. Also creates a dedicated CloudWatch log group for WAF logs.

```hcl
module "waf" {
  source       = "../modules/waf"
  name         = "my-waf"
  alb_arn      = module.alb.alb_arn
  rate_limit   = 2000
  tags         = var.tags
}
```

---

### `ecstask`
Creates an ECS Task Definition for Fargate (awsvpc networking, separate execution/task roles).

```hcl
module "ecs_task" {
  source                = "../modules/ecstask"
  family                = "my-task"
  cpu                   = 256
  memory                = 512
  execution_role_arn    = module.iam_exec_role.role_arn
  task_role_arn         = module.iam_task_role.role_arn
  container_definitions = jsonencode([...])
  tags                  = var.tags
}
```

---

### `ecsservice`
Creates an ECS Service with rolling deployment, circuit breaker auto-rollback, and ALB registration.

```hcl
module "ecs_service" {
  source                 = "../modules/ecsservice"
  name                   = "my-service"
  cluster_id             = module.ecs_cluster.cluster_id
  task_definition_arn    = module.ecs_task.task_definition_arn
  desired_count          = 2
  subnet_ids             = module.subnets.private_subnet_ids
  security_group_ids     = [module.sg_ecs.sg_id]
  target_group_arn       = module.tg.target_group_arn
  container_name         = "app"
  container_port         = 80
  enable_execute_command = true
  tags                   = var.tags
}
```

---

### `cwalarms`
Creates CloudWatch Alarms for ECS CPU, memory, ALB 5xx, and application error log counts,
with an SNS topic (KMS-encrypted) for notifications.

```hcl
module "alarms" {
  source              = "../modules/cwalarms"
  prefix              = "my-prefix"
  ecs_cluster_name    = module.ecs_cluster.cluster_name
  ecs_service_name    = module.ecs_service.service_name
  alb_arn_suffix      = module.alb.alb_arn_suffix
  log_group_name      = module.cwlog_app.log_group_name
  kms_key_arn         = module.kms.key_arn
  alarm_email         = "ops@example.com"
  cpu_threshold       = 75
  memory_threshold    = 75
  error_5xx_threshold = 5
  tags                = var.tags
}
```

---

## Tagging Policy

All resources must carry the following tags (enforced by Checkov policy gate):

```hcl
tags = {
  Project            = "GCC"
  Environment        = "Production"
  Owner              = "NTT"
  CostCenter         = "NTT"
  Terraform          = "True"
  DataClassification = "Internal"
}
```

---

## Workspace Convention

| Workspace | Purpose | tfvars file |
|---|---|---|
| `Production` | Live production environment | `workspaces/Production.tfvars` |

To add a new environment, create `workspaces/<Name>.tfvars` and add the workspace name +
IAM role ARN to `workspace_iam_roles` in the tfvars file.



---

## AWSArchitecture

![Diagram]("AWSArchitecture.jpg")