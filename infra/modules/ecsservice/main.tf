# Tracks load balancer config — any change here forces the service to be replaced
# (load_balancer block is immutable on existing ECS services)
resource "terraform_data" "lb_config" {
  input = {
    target_group_arn = var.target_group_arn
    container_name   = var.container_name
    container_port   = var.container_port
  }
}

resource "aws_ecs_service" "this" {
  name                               = var.name
  cluster                            = var.cluster_id
  task_definition                    = var.task_definition_arn
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  # Enable rolling updates with circuit breaker to auto-rollback failed deployments
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  lifecycle {
    ignore_changes       = [task_definition, desired_count]
    replace_triggered_by = [terraform_data.lb_config]
  }

  tags = var.tags

  enable_ecs_managed_tags = true
  enable_execute_command  = var.enable_execute_command
}
