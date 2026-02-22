"""
Shared pytest fixtures for orchestration tests.

All AWS calls are mocked using unittest.mock — no real AWS credentials required.

Each test file loads its own Lambda handler via _load_lambda() (defined in each
file) to avoid sys.modules name collisions when all handlers share the filename
'handler.py'. conftest.py provides only shared pytest fixtures.
"""

import os
import sys

import pytest

# Make scripts importable (deploy.py CLI)
SCRIPTS_ROOT = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "scripts")
)
if SCRIPTS_ROOT not in sys.path:
    sys.path.insert(0, SCRIPTS_ROOT)


@pytest.fixture
def valid_event():
    return {
        "environment": "Production",
        "region": "ap-southeast-1",
        "image_tag": "sha-5e3a1c7",
        "image_uri": (
            "992382521824.dkr.ecr.ap-southeast-1.amazonaws.com"
            "/ntt-gcc-production-app:sha-5e3a1c7"
        ),
        "endpoint_url": "https://app.ntt.demodevops.net",
        "cluster_name": "Ntt-Gcc-Production-Cluster",
        "service_name": "Ntt-Gcc-Production-Service",
        "task_family": "Ntt-Gcc-Production-Task",
        "container_name": "app",
        "log_group_name": "/ecs/app/ntt-gcc-production",
        "evidence_bucket": "ntt-gcc-production-alb-logs-992382521824",
    }


@pytest.fixture
def deploy_result():
    """Simulates the output from the Deploy Lambda stored in $.deploy."""
    return {
        "deployed": True,
        "new_task_def_arn": (
            "arn:aws:ecs:ap-southeast-1:992382521824"
            ":task-definition/Ntt-Gcc-Production-Task:42"
        ),
        "previous_task_def_arn": (
            "arn:aws:ecs:ap-southeast-1:992382521824"
            ":task-definition/Ntt-Gcc-Production-Task:41"
        ),
        "image_uri": (
            "992382521824.dkr.ecr.ap-southeast-1.amazonaws.com"
            "/ntt-gcc-production-app:sha-5e3a1c7"
        ),
    }


@pytest.fixture
def lambda_context():
    """Minimal Lambda context object."""
    class _Context:
        function_name = "test-function"
        memory_limit_in_mb = 128
        invoked_function_arn = "arn:aws:lambda:ap-southeast-1:123456789:function:test"
        aws_request_id = "test-request-id"
    return _Context()
