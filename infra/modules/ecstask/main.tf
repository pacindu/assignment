#checkov:skip=CKV_AWS_249:execution_role_arn and task_role_arn are separate variables bound to different IAM roles at the resource layer
#checkov:skip=CKV_AWS_97:The application requires write access to the filesystem (gunicorn tmp files, logs); read-only root filesystem is not compatible with this workload
#checkov:skip=CKV_AWS_336:The application requires write access to the filesystem (gunicorn tmp files, logs); read-only root filesystem is not compatible with this workload
resource "aws_ecs_task_definition" "this" {
  family                   = var.family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  container_definitions    = var.container_definitions

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  tags = var.tags
}
