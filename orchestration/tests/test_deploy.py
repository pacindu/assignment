"""
Unit tests for the ECS Deploy Lambda and the deploy.py CLI script.

All AWS calls are mocked — no real credentials required.
"""

import argparse
import importlib.util
import json
import os
import sys
from unittest.mock import MagicMock, call, patch

import pytest

_LAMBDA_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "lambda"))

def _load_lambda(unique_name, rel_path):
    abs_path = os.path.join(_LAMBDA_ROOT, rel_path)
    if unique_name not in sys.modules:
        spec = importlib.util.spec_from_file_location(unique_name, abs_path)
        mod = importlib.util.module_from_spec(spec)
        sys.modules[unique_name] = mod
        spec.loader.exec_module(mod)
    return sys.modules[unique_name]

deploy_handler = _load_lambda("deploy_handler", "deploy/handler.py")

import deploy as deploy_cli


# ---------------------------------------------------------------------------
# Helpers — mock ECS responses
# ---------------------------------------------------------------------------

PREV_TD_ARN = (
    "arn:aws:ecs:ap-southeast-1:992382521824"
    ":task-definition/Ntt-Gcc-Production-Task:41"
)
NEW_TD_ARN = (
    "arn:aws:ecs:ap-southeast-1:992382521824"
    ":task-definition/Ntt-Gcc-Production-Task:42"
)
IMAGE_URI = (
    "992382521824.dkr.ecr.ap-southeast-1.amazonaws.com"
    "/ntt-gcc-production-app:sha-5e3a1c7"
)


def _describe_services_response():
    return {
        "services": [
            {
                "serviceName": "Ntt-Gcc-Production-Service",
                "taskDefinition": PREV_TD_ARN,
                "desiredCount": 1,
                "runningCount": 1,
                "status": "ACTIVE",
            }
        ],
        "failures": [],
    }


def _describe_task_definition_response():
    return {
        "taskDefinition": {
            "taskDefinitionArn": PREV_TD_ARN,
            "family": "Ntt-Gcc-Production-Task",
            "revision": 41,
            "status": "ACTIVE",
            "networkMode": "awsvpc",
            "requiresCompatibilities": ["FARGATE"],
            "cpu": "256",
            "memory": "512",
            "executionRoleArn": "arn:aws:iam::992382521824:role/ecsExecutionRole",
            "taskRoleArn": "arn:aws:iam::992382521824:role/ecsTaskRole",
            "containerDefinitions": [
                {
                    "name": "app",
                    "image": "992382521824.dkr.ecr.ap-southeast-1.amazonaws.com"
                             "/ntt-gcc-production-app:sha-previous",
                    "essential": True,
                    "portMappings": [{"containerPort": 80, "protocol": "tcp"}],
                }
            ],
            "volumes": [],
            "placementConstraints": [],
            "tags": [
                {"key": "Project", "value": "GCC"},
                {"key": "Environment", "value": "Production"},
            ],
            "runtimePlatform": {
                "cpuArchitecture": "ARM64",
                "operatingSystemFamily": "LINUX",
            },
        }
    }


def _register_task_definition_response():
    return {
        "taskDefinition": {
            "taskDefinitionArn": NEW_TD_ARN,
            "family": "Ntt-Gcc-Production-Task",
            "revision": 42,
            "status": "ACTIVE",
        }
    }


def _make_ecs_client():
    mock = MagicMock()
    mock.describe_services.return_value = _describe_services_response()
    mock.describe_task_definition.return_value = _describe_task_definition_response()
    mock.register_task_definition.return_value = _register_task_definition_response()
    mock.update_service.return_value = {"service": {"serviceName": "Ntt-Gcc-Production-Service"}}
    return mock


# ---------------------------------------------------------------------------
# Deploy Lambda unit tests
# ---------------------------------------------------------------------------

class TestDeployLambda:

    def test_registers_new_task_definition_revision(self, valid_event, lambda_context):
        mock_ecs = _make_ecs_client()
        with patch("deploy_handler.boto3") as mock_boto3:
            mock_boto3.client.return_value = mock_ecs
            result = deploy_handler.handler(valid_event, lambda_context)

        assert result["deployed"] is True
        assert result["new_task_def_arn"] == NEW_TD_ARN
        assert result["previous_task_def_arn"] == PREV_TD_ARN

    def test_updates_container_image_in_task_definition(self, valid_event, lambda_context):
        mock_ecs = _make_ecs_client()
        with patch("deploy_handler.boto3") as mock_boto3:
            mock_boto3.client.return_value = mock_ecs
            deploy_handler.handler(valid_event, lambda_context)

        # Verify register_task_definition was called with updated image
        call_kwargs = mock_ecs.register_task_definition.call_args[1]
        container_defs = call_kwargs["containerDefinitions"]
        app_container = next(c for c in container_defs if c["name"] == "app")
        assert app_container["image"] == IMAGE_URI

    def test_calls_update_service_with_new_task_def(self, valid_event, lambda_context):
        mock_ecs = _make_ecs_client()
        with patch("deploy_handler.boto3") as mock_boto3:
            mock_boto3.client.return_value = mock_ecs
            deploy_handler.handler(valid_event, lambda_context)

        mock_ecs.update_service.assert_called_once_with(
            cluster=valid_event["cluster_name"],
            service=valid_event["service_name"],
            taskDefinition=NEW_TD_ARN,
            forceNewDeployment=True,
        )

    def test_raises_when_container_name_not_found(self, valid_event, lambda_context):
        event = {**valid_event, "container_name": "nonexistent-container"}
        mock_ecs = _make_ecs_client()
        with patch("deploy_handler.boto3") as mock_boto3:
            mock_boto3.client.return_value = mock_ecs
            with pytest.raises(ValueError, match="not found in task definition"):
                deploy_handler.handler(event, lambda_context)

    def test_raises_when_service_not_found(self, valid_event, lambda_context):
        from botocore.exceptions import ClientError
        mock_ecs = _make_ecs_client()
        mock_ecs.describe_services.return_value = {"services": [], "failures": []}
        with patch("deploy_handler.boto3") as mock_boto3:
            mock_boto3.client.return_value = mock_ecs
            with pytest.raises(ValueError, match="not found"):
                deploy_handler.handler(valid_event, lambda_context)

    def test_returns_correct_image_uri(self, valid_event, lambda_context):
        mock_ecs = _make_ecs_client()
        with patch("deploy_handler.boto3") as mock_boto3:
            mock_boto3.client.return_value = mock_ecs
            result = deploy_handler.handler(valid_event, lambda_context)

        assert result["image_uri"] == IMAGE_URI


# ---------------------------------------------------------------------------
# deploy.py CLI unit tests
# ---------------------------------------------------------------------------

class TestDeployCli:

    def _base_args(self):
        return argparse.Namespace(
            environment="Production",
            image_tag="sha-5e3a1c7",
            region="ap-southeast-1",
            state_machine_arn="arn:aws:states:ap-southeast-1:123:stateMachine:ntt-deploy",
            endpoint_url="https://app.ntt.demodevops.net",
            cluster_name="Ntt-Gcc-Production-Cluster",
            service_name="Ntt-Gcc-Production-Service",
            task_family="Ntt-Gcc-Production-Task",
            container_name="app",
            ecr_registry="992382521824.dkr.ecr.ap-southeast-1.amazonaws.com",
            ecr_repository="ntt-gcc-production-app",
            evidence_bucket="ntt-gcc-production-alb-logs-992382521824",
            log_group_name="/ecs/app/ntt-gcc-production",
            timeout=900,
            no_wait=False,
            dry_run=False,
        )

    def test_validate_args_passes_with_valid_input(self):
        args = self._base_args()
        # Should not raise or exit
        deploy_cli.validate_args(args)

    def test_validate_args_fails_with_wrong_environment(self):
        args = self._base_args()
        args.environment = "Dev"
        with pytest.raises(SystemExit) as exc_info:
            deploy_cli.validate_args(args)
        assert exc_info.value.code == 2

    def test_validate_args_fails_with_wrong_region(self):
        args = self._base_args()
        args.region = "eu-west-1"
        with pytest.raises(SystemExit) as exc_info:
            deploy_cli.validate_args(args)
        assert exc_info.value.code == 2

    def test_validate_args_fails_with_invalid_image_tag(self):
        args = self._base_args()
        args.image_tag = "tag with spaces"
        with pytest.raises(SystemExit) as exc_info:
            deploy_cli.validate_args(args)
        assert exc_info.value.code == 2

    def test_validate_args_fails_when_state_machine_arn_missing(self):
        args = self._base_args()
        args.state_machine_arn = None
        with pytest.raises(SystemExit) as exc_info:
            deploy_cli.validate_args(args)
        assert exc_info.value.code == 2

    def test_build_execution_input_constructs_correct_image_uri(self):
        args = self._base_args()
        payload = deploy_cli.build_execution_input(args)
        expected_uri = (
            "992382521824.dkr.ecr.ap-southeast-1.amazonaws.com"
            "/ntt-gcc-production-app:sha-5e3a1c7"
        )
        assert payload["image_uri"] == expected_uri

    def test_build_execution_input_includes_all_required_fields(self):
        args = self._base_args()
        payload = deploy_cli.build_execution_input(args)
        for field in [
            "environment", "region", "image_tag", "image_uri", "endpoint_url",
            "cluster_name", "service_name", "task_family", "container_name",
            "log_group_name", "evidence_bucket",
        ]:
            assert field in payload, f"Missing field: {field}"

    def test_dry_run_exits_without_starting_execution(self):
        args = self._base_args()
        args.dry_run = True
        with pytest.raises(SystemExit) as exc_info:
            deploy_cli.main.__wrapped__ if hasattr(deploy_cli.main, "__wrapped__") else None
            # Patch sys.argv and run main()
            with patch("sys.argv", [
                "deploy.py",
                "--environment", "Production",
                "--image-tag", "sha-5e3a1c7",
                "--state-machine-arn", "arn:aws:states:ap-southeast-1:123:stateMachine:x",
                "--endpoint-url", "https://app.ntt.demodevops.net",
                "--cluster-name", "Cluster",
                "--service-name", "Service",
                "--task-family", "Task",
                "--ecr-registry", "123.dkr.ecr.ap-southeast-1.amazonaws.com",
                "--ecr-repository", "ntt-app",
                "--evidence-bucket", "my-bucket",
                "--log-group-name", "/ecs/app",
                "--dry-run",
            ]):
                deploy_cli.main()
        assert exc_info.value.code == 0

    def test_start_execution_returns_arn(self):
        mock_sfn = MagicMock()
        mock_sfn.start_execution.return_value = {
            "executionArn": "arn:aws:states:ap-southeast-1:123:execution:ntt-deploy:exec-1",
            "startDate": "2026-02-22T12:00:00Z",
        }
        execution_input = {
            "environment": "Production",
            "image_tag": "sha-5e3a1c7",
        }
        arn = deploy_cli.start_execution(
            mock_sfn,
            "arn:aws:states:ap-southeast-1:123:stateMachine:ntt-deploy",
            execution_input,
        )
        assert arn.startswith("arn:aws:states:")
        mock_sfn.start_execution.assert_called_once()
