Assignment 1 — Secure AWS Landing Zone + App Deployment Pipeline (Terraform + CI/CD + Compliance)
 
Scenario
 
You are onboarding a new Gov workload in AWS (GCC/GCC+ style constraints). You must provision a secure, compliant baseline and deploy a containerised microservice through a CI/CD pipeline with policy gates.
 
What to build
 
A. Terraform Infrastructure (IaC)

                •             Create a Terraform repo with modules for:
                •             VPC across 2 AZs, public/private subnets, route tables, NAT gateway (or alternative if constrained)
                •             Security groups with least privilege
                •             IAM roles/policies for CI/CD and runtime (no *:*)
                •             CloudWatch log groups, alarms (CPU/memory/5xx), metrics filters
                •             KMS keys for encryption at rest (ECR, logs, S3, etc.)
                •             S3 bucket for Terraform state with:
                •             versioning, encryption, bucket policy (deny unencrypted, deny public), DynamoDB state locking
                •             Add terraform validate, fmt, tflint, and policy checks (OPA/Conftest or Checkov).

 
B. Application Deployment

                •             Deploy a sample service (e.g., Nginx or a simple API) to ECS Fargate or EKS (pick one and justify).
                •             Use ALB with TLS termination (ACM).
                •             Enforce secure headers and WAF association if applicable.

 
C. CI/CD

                •             Implement a pipeline (GitHub Actions / GitLab CI / Jenkins) that:
                •             Builds container image → pushes to ECR
                •             Runs unit tests + container scan (Trivy or equivalent)
                •             Terraform plan + approval gate → apply to a target env
                •             Deploys app with blue/green or rolling strategy
                •             Produces artefacts: plan output, security scan reports

 
D. Compliance / GCC angle

                •             Provide a short “GCC-ready controls map” stating how you addressed:
                •             encryption, least privilege IAM, logging/auditability, network segmentation
                •             Include how you would integrate with SHIP-HAT (even as stubs): e.g., “SHIP-HAT pre-deploy checks” stage.

 
Deliverables


                •             Repo link (or zip) with:
                •             /infra Terraform modules + README
                •             /app source + Dockerfile
                •             /pipelines CI config
                •             /docs architecture diagram + threat model (short)
                •             Sample outputs (screenshots or logs):
                •             terraform plan + apply evidence
                •             Deployed endpoint + health check
                •             Scan reports + policy gate results
 
What this tests
 
AWS + Terraform depth, modular design, CI/CD, security by design, logging/monitoring, compliance discipline, documentation clarity.








Assignment 2 — Workflow Orchestration “Self-Healing Deployment” (Automation + Scripts + Testing)

 

Scenario

 

A deployment frequently fails due to configuration drift, missing parameters, or transient AWS errors. Build an orchestration workflow that validates prerequisites, deploys, verifies, and rolls back automatically.

 

What to build

 

A. Orchestrator

Choose one (state your choice):

                •             Step Functions (preferred), or

                •             Argo Workflows, or

                •             Jenkins pipeline as orchestrator

 

Workflow requirements:

                1.           Pre-flight validation

                •             Validate required Terraform variables and environment config

                •             Validate AWS account/region constraints (simulate GCC restrictions)

                •             Validate that required tags exist (owner, data_classification, cost_center)

                2.           Deploy stage

                •             Apply infra changes (terraform apply)

                •             Deploy application revision

                3.           Post-deploy verification

                •             Run synthetic tests against endpoint (HTTP checks + auth header checks)

                •             Validate CloudWatch logs contain no ERROR pattern

                4.           Automated rollback

                •             If verification fails, rollback to prior stable version (ECS task definition rollback / Helm rollback)

                5.           Evidence + audit artefacts

                •             Upload workflow run summary to S3 (timestamped)

                •             Emit structured JSON log of outcome

 

B. Scripting

                •             Provide at least one robust script:

                •             e.g., deploy.sh or Python CLI that drives environment selection, config validation, and invokes orchestrator

                •             Must include:

                •             retry logic, input validation, clear error messages

 

C. Automated Testing

                •             Write tests for the scripts/workflow logic:

                •             Python pytest or Shell bats, plus HTTP checks

                •             Include a “negative test” suite that triggers rollback.

 

Deliverables

                •             Workflow definition (Step Functions ASL / Argo YAML / Jenkinsfile)

                •             Scripts + tests + README

                •             Example run outputs showing:

                •             success path

                •             failure path + rollback + evidence stored

 

What this tests

 

Real orchestration maturity, automation engineering, reliability mindset, test discipline, secure/observable operations.

 

Assignment 3 — Gov Cloud “Compliance-as-Code” + Jira-Driven Delivery (Policy Gates + Change Evidence)

 

Scenario

 

You are operating in a regulated environment. Any change must:

                •             be tied to a Jira ticket

                •             pass compliance gates

                •             provide evidence for audit (what changed, who approved, what controls passed)

 

What to build

 

A. Compliance-as-Code Gate

Implement a policy gate that fails builds if:

                •             Terraform resources are missing mandatory tags

                •             S3 buckets allow public access

                •             Security groups allow 0.0.0.0/0 on admin ports (22/3389)

                •             Logs are not enabled (CloudWatch / ALB access logs)

                •             IAM policies contain wildcard admin actions without justification

 

Use one:

                •             OPA/Conftest with custom rules, or

                •             Checkov with custom policies, or

                •             tfsec + custom checks

 

B. Jira Integration

                •             Pipeline must require:

                •             Jira ticket ID in branch name or PR title (e.g., GCC-1234-feature-x)

                •             Auto-comment to Jira (mock allowed if no Jira creds): generate a JSON payload that would be sent

                •             Generate a release note from commit messages and Jira IDs.

 

C. SHIP-HAT / Gov Tooling awareness

                •             Add a pipeline stage placeholder called SHIP-HAT Compliance Scan

                •             Document what it would check (baseline hardening, endpoint exposure, TLS config, logging)

                •             If you can’t run it, emulate with your own “SHIP-HAT-like” checks (shell/python).

 

D. Evidence Pack

Generate an “audit evidence bundle” per run:

                •             Terraform plan + apply logs

                •             Policy gate outputs

                •             Test results

                •             Deployed version + checksum

                •             Approval evidence (manual gate capture in pipeline)

 

Output this as a zip uploaded to S3 (or locally).

 

Deliverables

                •             Repo with /policies, /pipeline, /evidence

                •             Sample evidence bundle

                •             Short write-up: “How this supports regulated environments (GCC/GCC+)”

 

What this tests

 

Compliance engineering, policy-as-code, audit thinking, Jira discipline, delivery governance, pipeline maturity.

Evaluation Rubric (Use this for scoring)

 

(100 points total, consistent across all 3 assignments)

                •             Terraform quality & modularity — 20

                •             AWS architecture correctness & security — 20

                •             CI/CD implementation & gating — 20

                •             Orchestration + automation robustness — 15

                •             Testing depth (unit/integration/negative) — 15

                •             Documentation & operational clarity — 10


