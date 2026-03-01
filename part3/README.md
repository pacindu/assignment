# Assignment 3 — Gov Cloud Compliance-as-Code + Jira-Driven Delivery

Policy Gates · Jira Integration · SHIP-HAT Emulation · Evidence Pack

---

## Directory Structure

```
part3/
├── policies/                          # Checkov custom Python policies
│   ├── check_mandatory_tags.py        # CKV_CUSTOM_1 — 5 mandatory tags
│   ├── check_s3_public_access.py      # CKV_CUSTOM_2 — S3 public access block
│   ├── check_sg_admin_ports.py        # CKV_CUSTOM_3 — SG blocks 22/3389
│   ├── check_logging_enabled.py       # CKV_CUSTOM_4/5 — ALB & ECS logging
│   └── check_iam_wildcards.py         # CKV_CUSTOM_6 — IAM no Action:"*"
│
├── workflows/
│   └── compliance.yml                 # 4-job GitHub Actions workflow
│                                      # (in a real repo: .github/workflows/)
│
├── evidence/
│   └── sample/                        # Sample evidence bundle
│       ├── checkov-results.json
│       ├── shiphat-report.json
│       ├── jira-comment-payload.json
│       ├── release-notes.md
│       └── manifest.json
│
└── README.md
```

---

## Design Approach — Why Inline?

All pipeline logic lives **directly in `compliance.yml`** as inline `run:` steps using
Python heredocs. There are no separate wrapper scripts in a `pipeline/` directory.

**Benefits:**
- The workflow is self-contained — one file to read, one file to review
- No hidden indirection; every step's logic is visible in the CI log
- Custom Checkov *policies* stay as proper Python files (they are reusable policy
  definitions, not pipeline glue)

---

## A. Compliance-as-Code Gate (Checkov)

### Why Checkov?

Mature Python API for custom policies, built-in AWS resource coverage, native SARIF output
for GitHub Code Scanning. No separate Rego compiler or runtime needed.

### Custom Policies (6 checks)

| ID | File | Fails When |
|---|---|---|
| `CKV_CUSTOM_1` | `check_mandatory_tags.py` | Any taggable resource is missing `Project`, `Environment`, `Owner`, `CostCenter`, or `Terraform` |
| `CKV_CUSTOM_2` | `check_s3_public_access.py` | `aws_s3_bucket_public_access_block` does not have all 4 block settings = `true` |
| `CKV_CUSTOM_3` | `check_sg_admin_ports.py` | A security group allows `0.0.0.0/0` or `::/0` on ports 22 or 3389 |
| `CKV_CUSTOM_4` | `check_logging_enabled.py` | `aws_lb`/`aws_alb` does not have `access_logs { enabled = true }` |
| `CKV_CUSTOM_5` | `check_logging_enabled.py` | ECS task definition container uses a log driver other than `awslogs` |
| `CKV_CUSTOM_6` | `check_iam_wildcards.py` | An IAM policy statement has `Effect=Allow` and `Action="*"` |

### Running locally

```bash
pip install checkov

checkov \
  --directory infra/ \
  --framework terraform \
  --external-checks-dir part3/policies/ \
  --output cli
```

---

## B. Jira Integration

Every branch merged to `main` must follow the naming convention:

```
NTT-NNNN-short-description
e.g. NTT-1234-add-nacl-rules
```

### Real API comment (live posting)

The `jira-gate` job in `compliance.yml`:

1. Extracts `GCC-\d+` from the branch name or PR title — fails the build if not found
2. If `JIRA_API_TOKEN` and `JIRA_EMAIL` secrets are set, **POSTs a real comment** to
   the Jira ticket using the Jira Cloud REST API v3 (Basic Auth)
3. If credentials are not set, writes a mock payload and logs a warning — **does not fail**

#### Setting up real Jira integration

In your GitHub repo → **Settings → Secrets and variables → Actions**, add:

| Secret | Value |
|---|---|
| `JIRA_API_TOKEN` | Jira Cloud API token (Jira → Account Settings → Security → API tokens) |
| `JIRA_EMAIL` | Email address associated with the Jira account |

Optionally set a repository variable:

| Variable | Default |
|---|---|
| `JIRA_BASE_URL` | `https://ntt-gcc.atlassian.net` |

#### Jira REST API v3 call

```
POST {JIRA_BASE_URL}/rest/api/3/issue/{ticket}/comment
Authorization: Basic base64(JIRA_EMAIL:JIRA_API_TOKEN)
Content-Type: application/json
Body: Atlassian Document Format (ADF) v1
```

The comment body is generated inline in the `jira-gate` job.

---

## C. SHIP-HAT Compliance Scan

**What is SHIP-HAT?**

SHIP-HAT (Security & Hardening Assessment Tool) is a GovTech Singapore tool mandated for
services hosted on GCC/GCC+. It validates baseline OS/runtime hardening, TLS configuration,
security response headers, exposed admin interfaces, and logging completeness.

Because SHIP-HAT is an internal GovTech tool, the `compliance-gates` job emulates the same
check categories using inline Python:

| Category | Check ID | What it verifies |
|---|---|---|
| TLS hardening | `TLS-01` | Endpoint accepts TLS 1.2+ |
| Security headers | `SEC-01` | HSTS, X-Content-Type-Options, X-Frame-Options, CSP, Cache-Control |
| Redirect | `SEC-02` | HTTP → HTTPS redirect (301/302/307/308) |
| Endpoint | `EXP-01` | `/health` returns HTTP 200 |
| IaC: S3 | `IAC-01` | No `acl = "public-read"` in Terraform |
| IaC: admin ports | `IAC-02` | No port 22/3389 open to `0.0.0.0/0` |
| IaC: logging | `IAC-03` | `aws_cloudwatch_log_group` present |
| IaC: ALB logs | `IAC-04` | `access_logs` block present |
| IaC: KMS | `IAC-05` | `aws_kms_key` present |
| IaC: WAF | `IAC-06` | `aws_wafv2_web_acl` present |

Live endpoint probes (TLS-01, SEC-01, SEC-02, EXP-01) are skipped if `ENDPOINT_URL` is
not set — they are marked `SKIP` rather than `FAIL`.

---

## D. Evidence Pack

Every pipeline run produces a timestamped ZIP archive containing:

| File | Source |
|---|---|
| `checkov-results.json` | Checkov custom policy gate output |
| `shiphat-report.json` | SHIP-HAT-like scan report |
| `jira-comment-payload.json` | Jira REST comment (real or mock) |
| `release-notes.md` | Git-derived release notes with Jira ticket links |
| `terraform-plan.txt` | `terraform plan` output (added by infra workflow) |
| `terraform-apply.txt` | `terraform apply` output (added by infra workflow) |
| `manifest.json` | SHA-256 checksums + metadata (auto-generated) |

The bundle is uploaded as a **GitHub Actions artifact** with 90-day retention:

```
evidence-bundle-{run_id}   (downloadable from the Actions run summary)
```

---

## Pipeline — GitHub Actions (`compliance.yml`)

```
[push to GCC-* or main / PR to main]
         │
         ▼
    jira-gate           ← fails if branch has no NTT-NNNN; posts real Jira comment
         │
    ┌────┴────┐
    ▼         ▼
compliance  release-notes    ← parallel
gates           │
(checkov +      │
 shiphat)       │
    │           │
    └─────┬─────┘
          ▼
    evidence-pack       ← always runs; bundles ZIP + uploads as artifact
```

### Required secrets

| Secret | Required | Purpose |
|---|---|---|
| `JIRA_API_TOKEN` | Optional | Enables real Jira comment posting |
| `JIRA_EMAIL` | Optional | Jira auth (paired with API token) |

### Optional variables

| Variable | Default | Purpose |
|---|---|---|
| `JIRA_BASE_URL` | `https://ntt-gcc.atlassian.net` | Jira Cloud instance URL |
| `ENDPOINT_URL` | `https://app.ntt.demodevops.net` | App endpoint for live SHIP-HAT probes |

---

## How This Supports Regulated Environments (GCC / GCC+)

### Traceability — every change tied to a Jira ticket

The `jira-gate` enforces `NTT-NNNN-*` branch naming, linking every commit to an approved
change request. Satisfies IM8 Clause 7.4 (Change Management) and GCC's requirement that all
production changes are authorised and tracked in the organisation's project management system.

### Policy-as-Code — controls are automated, not manual

Six custom Checkov policies codify the most common GCC audit failures: missing mandatory tags,
public S3 buckets, open admin ports, disabled logging, and IAM wildcards. Encoded as code they
are version-controlled, peer-reviewed, and enforced on every pull request.

### Continuous compliance — gates run on every push

The workflow triggers on every `GCC-*` branch push and every PR to `main`. Developers receive
immediate feedback in the PR check suite. SARIF upload to GitHub Code Scanning surfaces
violations inline on changed files.

### Audit evidence — immutable, cryptographically verified

The evidence bundle (ZIP + SHA-256 manifest) is uploaded as a GitHub Actions artifact with
90-day retention. The artifact name includes the run ID, making each run's evidence unique.

### SHIP-HAT alignment — baseline hardening verified before every deployment

The `compliance-gates` job verifies the same hardening categories as SHIP-HAT (TLS version,
security headers, HTTP redirect, logging, encryption, WAF) on every pipeline run, providing
continuous assurance rather than a one-time pre-launch check.

### Separation of duties — gates enforced by the pipeline, not developers

No developer can bypass the Jira gate, Checkov gate, or SHIP-HAT scan by committing directly
to `main`. All production changes go through a branch + PR workflow.

---

## Residual Gaps

| Gap | Remediation |
|---|---|
| Jira integration falls back to mock if secrets not set | Add `JIRA_API_TOKEN` and `JIRA_EMAIL` to GitHub Secrets |
| No human approval gate before `apply` | Add a GitHub Environment protection rule with required reviewers |
| SHIP-HAT live probes skipped without `ENDPOINT_URL` | Set `ENDPOINT_URL` variable in GitHub repo settings |
| Checkov custom policies not unit-tested | Add `pytest` tests using `checkov.common.runners.runner_registry` mocks |
