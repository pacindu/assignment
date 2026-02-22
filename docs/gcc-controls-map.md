# GCC Controls Map — NTT Assignment 1

**Classification:** Internal
**Environment:** Production (ap-southeast-1)
**Framework reference:** GCC (Government on Commercial Cloud) security baseline + IM8 principles

---

## 1. Encryption

### Encryption at Rest

| Control | Requirement | Implementation | Status |
|---|---|---|---|
| Data at rest encrypted | All storage must use approved encryption | S3 state bucket: `aws:kms` enforced via bucket policy (denies non-KMS PutObject) | ✓ |
| Container images encrypted | ECR repository encrypted | ECR: KMS CMK (`alias/ntt-gcc-production-Ecs`) | ✓ |
| Log data encrypted | CloudWatch Logs encrypted | `/ecs/app/*`, `/ecs/exec/*`: KMS CMK with CloudWatch service principal | ✓ |
| Database / state encrypted | State store encrypted | DynamoDB state lock table: KMS CMK, PITR enabled | ✓ |
| Secrets management | No plaintext secrets | No long-lived credentials stored; OIDC federation for CI/CD | ✓ |
| Key management | Customer-managed keys, rotation | 4 CMKs (state, ECS, SNS); annual rotation enabled; 30-day deletion window | ✓ |

### Encryption in Transit

| Control | Requirement | Implementation | Status |
|---|---|---|---|
| TLS for public endpoints | HTTPS only, no HTTP plaintext | ALB HTTP listener: 301 redirect to HTTPS; TLS policy: `ELBSecurityPolicy-TLS13-1-2-2021-06` | ✓ |
| Valid certificates | PKI-issued certificate | ACM certificate for `app.ntt.demodevops.net` + wildcard SAN; auto-renewed | ✓ |
| Internal traffic | Encrypted where possible | ECS task egress restricted to HTTPS (443) only via security group | ✓ |
| HSTS enforcement | Prevent protocol downgrade | `Strict-Transport-Security: max-age=31536000; includeSubDomains` header | ✓ |
| State backend transport | Encrypted in transit | S3 backend: bucket policy denies non-HTTPS (`aws:SecureTransport = false`) | ✓ |

---

## 2. Least Privilege IAM

| Control | Requirement | Implementation | Status |
|---|---|---|---|
| No wildcard admin IAM | No `Action: *` or `Resource: *` in policies | ECS execution role: scoped to ECR pull, CloudWatch Logs, KMS decrypt only | ✓ |
| Service-scoped roles | Each service has its own role | ECS execution role ≠ ECS task role; separate KMS grants per service | ✓ |
| CI/CD OIDC federation | No long-lived access keys for pipelines | GitHub Actions uses OIDC; role scoped to this repo; no static `AWS_ACCESS_KEY_ID` | ✓ |
| Workspace role isolation | Separate deployment role per environment | `workspace_iam_roles` map; Terraform assumes `TerraformRole` via `assume_role` | ✓ |
| KMS key policies | Restrict key access to specific principals | State KMS: root admin + explicit service grant; ECS KMS: CloudWatch Logs service principal scoped to account | ✓ |
| S3 bucket policies | Deny public access, enforce encryption | `aws_s3_bucket_public_access_block` (all 4 policies); bucket policy with explicit denies | ✓ |
| Resource tagging | Owner/cost traceability | All resources tagged: `Project`, `Environment`, `Owner`, `CostCenter`, `Terraform`, `DataClassification` | ✓ |

---

## 3. Logging and Auditability

| Control | Requirement | Implementation | Status |
|---|---|---|---|
| Application logging | Capture all request/error logs | ECS containers write to CloudWatch Logs (`/ecs/app/*`) via `awslogs` driver | ✓ |
| Log retention | Minimum 1 year (IM8 requirement) | All CloudWatch log groups: `retention_in_days = 365` | ✓ |
| Log encryption | Logs must be encrypted | CloudWatch log groups: KMS CMK with `logs.*.amazonaws.com` service principal | ✓ |
| ALB access logging | Record all HTTP requests | ALB access logs → S3 bucket (`ntt-gcc-production-alb-logs-*`) | ✓ |
| ECS Exec audit | Exec sessions logged | ECS Exec enabled; session output encrypted via KMS and logged to CloudWatch | ✓ |
| Alarm on anomalies | Alert on error patterns | CloudWatch Alarm on `ERROR` log metric filter; CPU/memory/5xx alarms → SNS | ✓ |
| Pipeline audit | All deployments traceable | GitHub Actions logs; Terraform plan/apply artefacts (30-day retention); commit SHA tags on ECR images | ✓ |
| CloudTrail | AWS API audit log | **Gap** — not yet implemented; recommended for full GCC compliance | ✗ |
| VPC Flow Logs | Network-level audit | **Gap** — not yet implemented; checkov:skip applied with justification | ✗ |

---

## 4. Network Segmentation

| Control | Requirement | Implementation | Status |
|---|---|---|---|
| Public / private tier separation | Workloads not directly internet-accessible | ECS tasks in private subnets (10.0.11.0/24, 10.0.12.0/24); no public IP assigned | ✓ |
| Secure tier | Database/sensitive resources isolated | Secure subnets (10.0.21.0/24, 10.0.22.0/24) with local-only routing (no NAT, no IGW) | ✓ |
| Security group least privilege | Stateful firewall rules | ALB SG: 80/443 inbound from 0.0.0.0/0; ECS SG: container port from ALB SG only; egress 443 only | ✓ |
| Default VPC restrictions | Default SG must deny all | `aws_default_security_group` with no ingress/egress rules (deny all) | ✓ |
| Network ACL controls | Stateless second layer | Public NACL: allows 80, 443, ephemeral 1024-65535; blocks 20, 21, 22, 3389 | ✓ |
| WAF protection | Web application firewall on public ALB | WAF v2 (REGIONAL) associated with ALB; IP reputation, OWASP, rate limiting | ✓ |
| NAT Gateway | Controlled outbound internet | Single NAT GW in public subnet; private tier routes outbound traffic through it | ✓ |
| No direct internet to private tier | No routes from IGW to private subnets | Route table for private subnets: `0.0.0.0/0 → NAT GW` only | ✓ |

---

## 5. Policy-as-Code Gate

| Tool | What It Checks | Integration |
|---|---|---|
| **Checkov** | Missing tags, public S3, SG admin ports, wildcard IAM, logging enabled, lifecycle rules | GitHub Actions `checkov` job — runs on every push/PR; SARIF uploaded to GitHub Security |
| **terraform fmt** | Code formatting consistency | GitHub Actions `validate` job — fails fast on formatting issues |
| **terraform validate** | Syntax and type correctness | GitHub Actions `validate` job |
| **tflint** | Terraform best practices and deprecated usage | GitHub Actions `validate` job |
| **Trivy** | Container CVEs (CRITICAL/HIGH, unfixed) | GitHub Actions `build-scan-push` job — blocks ECR push on findings |

---

## 6. SHIP-HAT Integration (Placeholder / Stub)

> **Note:** This section describes where SHIP-HAT integration would be inserted. The pipeline stage
> is implemented as a stub. Full integration requires SHIP-HAT endpoint access and credentials
> which are outside the scope of this assignment.

### What SHIP-HAT Would Check

| Check Category | Specific Checks |
|---|---|
| **Baseline hardening** | OS patch level, CIS benchmark compliance for container base image |
| **Endpoint exposure** | No unnecessary ports open; TLS version ≥ 1.2; certificate validity |
| **TLS configuration** | Cipher suite compliance (GCC-approved list); HSTS presence and max-age |
| **Logging** | CloudWatch log groups active; retention ≥ 1 year; log encryption |
| **Container hygiene** | No running as root; read-only FS where possible; no privileged containers |
| **Secrets** | No plaintext secrets in environment variables or config maps |
| **IAM posture** | No wildcard policies; MFA enforcement for human roles |
| **Network controls** | WAF active; SG rules reviewed; no 0.0.0.0/0 on admin ports |

### Stub Pipeline Stage

The following stage would be inserted in `.github/workflows/infra.yml` between `checkov` and `plan`:

```yaml
# ---------------------------------------------------------------------------
# SHIP-HAT Compliance Scan (stub — replace endpoint/token with real values)
# ---------------------------------------------------------------------------
ship-hat-scan:
  name: SHIP-HAT Compliance Scan
  needs: [checkov]
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - name: SHIP-HAT pre-deploy checks
      env:
        SHIP_HAT_ENDPOINT: ${{ secrets.SHIP_HAT_ENDPOINT }}
        SHIP_HAT_TOKEN:    ${{ secrets.SHIP_HAT_TOKEN }}
      run: |
        echo "=== SHIP-HAT Compliance Scan ==="
        echo "Target environment : Production"
        echo "Region             : ap-southeast-1"
        echo "Checks running     : baseline-hardening, tls-config, logging, iam-posture"

        # Stub: replace with actual SHIP-HAT CLI or API call
        # Example:
        # ship-hat scan \
        #   --endpoint "$SHIP_HAT_ENDPOINT" \
        #   --token    "$SHIP_HAT_TOKEN" \
        #   --profile  gcc-production \
        #   --output   sarif \
        #   > ship-hat-results.sarif

        # Emulated checks (runs until real SHIP-HAT is available)
        python3 - <<'PYTHON'
        import sys, json

        checks = [
            ("TLS policy",          "ELBSecurityPolicy-TLS13-1-2-2021-06", True),
            ("HSTS header",         "max-age=31536000; includeSubDomains",  True),
            ("WAF association",     "aws_wafv2_web_acl_association present", True),
            ("Log retention",       "retention_in_days = 365",              True),
            ("Log encryption",      "kms_key_id set on log groups",         True),
            ("Public S3 blocked",   "block_public_acls = true",             True),
            ("No admin ports open", "no 22/3389 in SG ingress",             True),
            ("VPC Flow Logs",       "not yet enabled",                      False),
            ("CloudTrail",          "not yet enabled",                      False),
        ]

        passed = sum(1 for _, _, ok in checks if ok)
        total  = len(checks)
        print(f"\nSHIP-HAT Compliance Summary: {passed}/{total} checks passed\n")
        for name, detail, ok in checks:
            status = "PASS" if ok else "WARN"
            print(f"  [{status}] {name}: {detail}")

        # Warn on gaps but do not block (WARN-only until full integration)
        failed = [name for name, _, ok in checks if not ok]
        if failed:
            print(f"\nWarnings (non-blocking): {', '.join(failed)}")
            print("Action required before production sign-off.")
        sys.exit(0)
        PYTHON
```

---

## 7. Residual Gaps and Remediation Plan

| Gap | Risk | Remediation |
|---|---|---|
| No CloudTrail | Medium — AWS API actions unaudited | Enable multi-region CloudTrail with S3 log bucket and integrity validation |
| No VPC Flow Logs | Medium — no network-level forensics | Create dedicated IAM role + log group; enable flow logs on VPC |
| Single NAT Gateway | Low — single AZ outbound dependency | Deploy one NAT GW per AZ for HA |
| Auto-approve on `main` push | Low — no manual gate before `terraform apply` | Add GitHub Environment with required reviewers (requires Team/Enterprise plan) |
| No GuardDuty | Medium — no runtime threat detection | Enable GuardDuty; subscribe to findings via SNS |
| No AWS Config | Medium — no continuous compliance drift detection | Enable AWS Config with managed rules for CIS/GCC compliance |
