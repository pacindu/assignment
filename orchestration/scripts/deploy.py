#!/usr/bin/env python3
"""
deploy.py — NTT GCC Self-Healing Deployment CLI

Invokes the Step Functions state machine that orchestrates:
  1. Pre-flight validation (region, account, tags)
  2. ECS rolling deployment (new task definition + service update)
  3. Post-deploy verification (HTTP checks + CloudWatch Logs)
  4. Automated rollback on failure
  5. Evidence upload to S3

Usage:
  python deploy.py \\
      --environment Production \\
      --image-tag sha-5e3a1c7 \\
      --state-machine-arn arn:aws:states:ap-southeast-1:ACCOUNT:stateMachine:ntt-gcc-production-deploy \\
      --endpoint-url https://app.ntt.demodevops.net \\
      ...

All flags can also be set via environment variables (see --help for names).

Exit codes:
  0 — execution SUCCEEDED
  1 — execution FAILED, TIMED_OUT, or ABORTED
  2 — input validation error (deployment not started)
"""

import argparse
import json
import logging
import os
import sys
import time
from datetime import datetime

import boto3
from botocore.exceptions import BotoCoreError, ClientError

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
    level=logging.INFO,
    stream=sys.stdout,
)
logger = logging.getLogger("deploy")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
ALLOWED_ENVIRONMENTS = {"Production", "Staging"}
ALLOWED_REGION = "ap-southeast-1"

MAX_RETRIES = 3
RETRY_BACKOFF_BASE = 2   # wait = base ** attempt (seconds)
POLL_INTERVAL = 15       # seconds between state machine status polls
DEFAULT_TIMEOUT = 900    # 15 minutes


# ---------------------------------------------------------------------------
# Retry helper
# ---------------------------------------------------------------------------

def with_retry(fn, max_retries: int = MAX_RETRIES, backoff_base: int = RETRY_BACKOFF_BASE):
    """Call fn() with exponential backoff on transient AWS errors."""
    _TRANSIENT_CODES = {
        "ThrottlingException",
        "RequestExpiredException",
        "ServiceUnavailableException",
        "InternalFailure",
        "RequestLimitExceeded",
    }
    for attempt in range(1, max_retries + 1):
        try:
            return fn()
        except (BotoCoreError, ClientError) as exc:
            code = getattr(exc, "response", {}).get("Error", {}).get("Code", "")
            if attempt < max_retries and code in _TRANSIENT_CODES:
                wait = backoff_base ** attempt
                logger.warning(
                    "Transient AWS error on attempt %d/%d (%s). Retrying in %ds…",
                    attempt, max_retries, code, wait,
                )
                time.sleep(wait)
            else:
                raise
    raise RuntimeError(f"Operation failed after {max_retries} retries")


# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

def validate_args(args) -> None:
    """Validate CLI arguments. Exits with code 2 on the first set of errors."""
    errors = []

    if args.environment not in ALLOWED_ENVIRONMENTS:
        errors.append(
            f"--environment must be one of {sorted(ALLOWED_ENVIRONMENTS)}, "
            f"got: {args.environment!r}"
        )

    if not args.image_tag:
        errors.append("--image-tag is required")
    elif not _is_valid_tag(args.image_tag):
        errors.append(
            f"--image-tag '{args.image_tag}' contains invalid characters. "
            "Allowed: alphanumeric, dash, dot, underscore."
        )

    if args.region != ALLOWED_REGION:
        errors.append(
            f"--region must be '{ALLOWED_REGION}' (GCC constraint), "
            f"got: {args.region!r}"
        )

    required_args = {
        "--state-machine-arn / STATE_MACHINE_ARN": args.state_machine_arn,
        "--endpoint-url / ENDPOINT_URL": args.endpoint_url,
        "--cluster-name / CLUSTER_NAME": args.cluster_name,
        "--service-name / SERVICE_NAME": args.service_name,
        "--task-family / TASK_FAMILY": args.task_family,
        "--ecr-registry / ECR_REGISTRY": args.ecr_registry,
        "--ecr-repository / ECR_REPOSITORY": args.ecr_repository,
        "--evidence-bucket / EVIDENCE_BUCKET": args.evidence_bucket,
        "--log-group-name / LOG_GROUP_NAME": args.log_group_name,
    }
    for name, value in required_args.items():
        if not value:
            errors.append(f"{name} is required")

    if errors:
        logger.error("Input validation failed with %d error(s):", len(errors))
        for i, err in enumerate(errors, 1):
            logger.error("  %d. %s", i, err)
        sys.exit(2)


def _is_valid_tag(tag: str) -> bool:
    import re
    return bool(re.match(r"^[\w.\-]+$", tag))


# ---------------------------------------------------------------------------
# Execution helpers
# ---------------------------------------------------------------------------

def build_execution_input(args) -> dict:
    """Construct the Step Functions execution input payload."""
    image_uri = f"{args.ecr_registry}/{args.ecr_repository}:{args.image_tag}"
    return {
        "environment": args.environment,
        "region": args.region,
        "image_tag": args.image_tag,
        "image_uri": image_uri,
        "endpoint_url": args.endpoint_url,
        "cluster_name": args.cluster_name,
        "service_name": args.service_name,
        "task_family": args.task_family,
        "container_name": args.container_name,
        "log_group_name": args.log_group_name,
        "evidence_bucket": args.evidence_bucket,
    }


def start_execution(sfn_client, state_machine_arn: str, execution_input: dict) -> str:
    """Start a Step Functions execution and return the execution ARN."""
    ts = datetime.utcnow().strftime("%Y%m%dT%H%M%S")
    raw_name = (
        f"deploy-{execution_input['environment']}-"
        f"{execution_input['image_tag']}-{ts}"
    )
    # Step Functions execution names: letters, numbers, +!@.()-=_ — max 80 chars
    execution_name = "".join(
        c if c.isalnum() or c in "-_." else "-" for c in raw_name
    )[:80]

    def _start():
        return sfn_client.start_execution(
            stateMachineArn=state_machine_arn,
            name=execution_name,
            input=json.dumps(execution_input),
        )

    response = with_retry(_start)
    arn = response["executionArn"]
    logger.info("Execution started: %s", arn)
    return arn


def poll_execution(
    sfn_client,
    execution_arn: str,
    timeout: int = DEFAULT_TIMEOUT,
    poll_interval: int = POLL_INTERVAL,
) -> tuple[str, dict]:
    """
    Poll a Step Functions execution until terminal state or timeout.

    Returns (status, output) where status ∈ {SUCCEEDED, FAILED, TIMED_OUT, ABORTED}.
    """
    deadline = time.time() + timeout
    logger.info("Polling execution (timeout=%ds, interval=%ds)…", timeout, poll_interval)
    start = time.time()

    while time.time() < deadline:
        def _describe():
            return sfn_client.describe_execution(executionArn=execution_arn)

        response = with_retry(_describe)
        status = response["status"]

        if status != "RUNNING":
            output = {}
            if status == "SUCCEEDED" and response.get("output"):
                try:
                    output = json.loads(response["output"])
                except json.JSONDecodeError:
                    pass
            elapsed = int(time.time() - start)
            logger.info("Execution reached terminal state '%s' in %ds.", status, elapsed)
            return status, output

        elapsed = int(time.time() - start)
        logger.info("RUNNING… (%ds elapsed)", elapsed)
        time.sleep(poll_interval)

    logger.error("Execution did not complete within %ds.", timeout)
    return "TIMED_OUT", {}


# ---------------------------------------------------------------------------
# Argument parser
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="deploy.py",
        description="NTT GCC — invoke the self-healing Step Functions deployment workflow",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    # Required
    p.add_argument(
        "--environment", required=True,
        help="Target environment (Production | Staging)",
    )
    p.add_argument(
        "--image-tag", required=True,
        help="Docker image tag to deploy (e.g. git commit SHA: sha-5e3a1c7)",
    )
    # AWS / connection
    p.add_argument(
        "--region", default=os.getenv("AWS_REGION", ALLOWED_REGION),
        help="AWS region [env: AWS_REGION]",
    )
    p.add_argument(
        "--state-machine-arn", default=os.getenv("STATE_MACHINE_ARN"),
        help="Step Functions state machine ARN [env: STATE_MACHINE_ARN]",
    )
    # Application config
    p.add_argument(
        "--endpoint-url", default=os.getenv("ENDPOINT_URL"),
        help="Application HTTPS endpoint (e.g. https://app.ntt.demodevops.net) [env: ENDPOINT_URL]",
    )
    p.add_argument(
        "--cluster-name", default=os.getenv("CLUSTER_NAME"),
        help="ECS cluster name [env: CLUSTER_NAME]",
    )
    p.add_argument(
        "--service-name", default=os.getenv("SERVICE_NAME"),
        help="ECS service name [env: SERVICE_NAME]",
    )
    p.add_argument(
        "--task-family", default=os.getenv("TASK_FAMILY"),
        help="ECS task definition family [env: TASK_FAMILY]",
    )
    p.add_argument(
        "--container-name", default=os.getenv("CONTAINER_NAME", "app"),
        help="Container name inside the task definition [env: CONTAINER_NAME]",
    )
    p.add_argument(
        "--ecr-registry", default=os.getenv("ECR_REGISTRY"),
        help="ECR registry URL (e.g. 123456789.dkr.ecr.ap-southeast-1.amazonaws.com) [env: ECR_REGISTRY]",
    )
    p.add_argument(
        "--ecr-repository", default=os.getenv("ECR_REPOSITORY"),
        help="ECR repository name [env: ECR_REPOSITORY]",
    )
    p.add_argument(
        "--evidence-bucket", default=os.getenv("EVIDENCE_BUCKET"),
        help="S3 bucket name for evidence artefacts [env: EVIDENCE_BUCKET]",
    )
    p.add_argument(
        "--log-group-name", default=os.getenv("LOG_GROUP_NAME"),
        help="CloudWatch log group name for the application [env: LOG_GROUP_NAME]",
    )
    # Behaviour
    p.add_argument(
        "--timeout", type=int, default=DEFAULT_TIMEOUT,
        help="Maximum seconds to wait for the execution to complete",
    )
    p.add_argument(
        "--no-wait", action="store_true",
        help="Fire-and-forget: return immediately after starting the execution",
    )
    p.add_argument(
        "--dry-run", action="store_true",
        help="Print the execution input payload without starting the state machine",
    )
    return p


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    # Validate inputs before touching AWS
    validate_args(args)

    execution_input = build_execution_input(args)

    if args.dry_run:
        print("\n[DRY RUN] Would start Step Functions execution with:")
        print(json.dumps(execution_input, indent=2))
        sys.exit(0)

    logger.info("Starting deployment: environment=%s image_tag=%s",
                args.environment, args.image_tag)

    sfn = boto3.client("stepfunctions", region_name=args.region)
    execution_arn = start_execution(sfn, args.state_machine_arn, execution_input)

    if args.no_wait:
        logger.info("--no-wait set. Execution ARN: %s", execution_arn)
        print(json.dumps({"execution_arn": execution_arn, "status": "STARTED"}))
        sys.exit(0)

    status, output = poll_execution(sfn, execution_arn, timeout=args.timeout)

    # -----------------------------------------------------------------------
    # Emit structured audit log
    # -----------------------------------------------------------------------
    audit = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "execution_arn": execution_arn,
        "status": status,
        "environment": args.environment,
        "image_tag": args.image_tag,
        "evidence": output.get("evidence", {}),
    }
    separator = "=" * 64
    print(f"\n{separator}")
    print("DEPLOYMENT AUDIT LOG")
    print(separator)
    print(json.dumps(audit, indent=2))
    print(separator)

    if status == "SUCCEEDED":
        logger.info("Deployment SUCCEEDED.")
        sys.exit(0)
    else:
        logger.error(
            "Deployment %s. Check the Step Functions console or S3 evidence "
            "artefact for details.",
            status,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
