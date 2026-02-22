# Threat Model — NTT GCC Assignment 1

**Date:** 2026-02
**Scope:** VPC landing zone + ECS Fargate application + CI/CD pipeline
**Classification:** Internal
**Methodology:** STRIDE-lite (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege)

---

## System Overview

```
[Internet User] → [WAF] → [ALB/TLS] → [ECS Fargate] → [CloudWatch Logs]
                                              │
                               [ECR] ←── [CI/CD Pipeline]
                                              │
                                    [S3 State + KMS + DynamoDB]
```

**Trust boundaries:**
- **External / Untrusted:** Internet, public CIDR
- **Edge:** WAF, ALB (public subnets)
- **Application:** ECS tasks (private subnets)
- **Data / Control:** KMS, S3, DynamoDB, CloudWatch (AWS-managed plane)
- **CI/CD:** GitHub Actions runners (external, OIDC-federated)

---

## Threat Analysis

### T1 — DDoS / Volumetric Attack

| Attribute | Detail |
|---|---|
| **Category** | Denial of Service |
| **Actor** | External attacker |
| **Attack vector** | Flood of HTTP requests to ALB endpoint |
| **Impact** | Service unavailability; cost amplification |
| **Likelihood** | Medium |
| **Mitigations** | WAF rate limiting (2000 req/5 min per IP); AWS Shield Standard (included); ALB scales horizontally; ECS auto-scaling up to max capacity |
| **Residual risk** | Low — application-layer slowloris or low-rate attacks not fully mitigated without Shield Advanced |

---

### T2 — Web Application Attack (SQLi, XSS, Command Injection)

| Attribute | Detail |
|---|---|
| **Category** | Tampering, Elevation of Privilege |
| **Actor** | External attacker |
| **Attack vector** | Malicious payloads in HTTP request body/headers |
| **Impact** | Data exfiltration, remote code execution, privilege escalation |
| **Likelihood** | Medium |
| **Mitigations** | WAF `AWSManagedRulesCommonRuleSet` (OWASP core); `AWSManagedRulesKnownBadInputsRuleSet` (Log4Shell, Spring4Shell); `drop_invalid_header_fields = true` on ALB; Content-Security-Policy header (`default-src 'none'`); X-XSS-Protection header |
| **Residual risk** | Low for known attack patterns; zero-days remain a risk |

---

### T3 — Container Image Compromise / Supply Chain Attack

| Attribute | Detail |
|---|---|
| **Category** | Tampering |
| **Actor** | Malicious third-party package, compromised base image |
| **Attack vector** | Vulnerable dependency or malicious layer in container image |
| **Impact** | Arbitrary code execution in container, lateral movement |
| **Likelihood** | Medium |
| **Mitigations** | Trivy scan in CI pipeline (blocks CRITICAL/HIGH unfixed CVEs before push); ECR image scanning; immutable ECR tags; pinned base image (`python:3.12-slim`); minimal package surface |
| **Residual risk** | Medium — zero-day CVEs undetected until vendor patches |

---

### T4 — Credential / Secret Theft

| Attribute | Detail |
|---|---|
| **Category** | Information Disclosure, Elevation of Privilege |
| **Actor** | External attacker, malicious insider |
| **Attack vector** | Stolen AWS credentials, leaked GitHub secrets, SSRF to IMDS |
| **Impact** | Full AWS account takeover |
| **Likelihood** | Low |
| **Mitigations** | GitHub Actions OIDC (no long-lived keys stored as secrets); OIDC role scoped to this repo only; ECS task metadata endpoint uses IMDSv2 (session-oriented); IAM roles scoped per service (no `*:*`); KMS key access restricted to specific service principals |
| **Residual risk** | Low |

---

### T5 — Unauthorised Data Access / Exfiltration

| Attribute | Detail |
|---|---|
| **Category** | Information Disclosure |
| **Actor** | Compromised ECS task, malicious insider |
| **Attack vector** | ECS task egress to exfiltration endpoint; S3 bucket misconfiguration |
| **Impact** | Data leak of state files, logs, or application data |
| **Likelihood** | Low |
| **Mitigations** | ECS tasks in private subnets (no direct internet inbound); egress restricted to HTTPS (443) only via security group; S3 state bucket: public access blocked (all 4 policies), bucket policy denies non-HTTPS; CloudWatch logs: KMS-encrypted; ALB access logs: KMS-encrypted S3 |
| **Residual risk** | Low — outbound 443 still allows HTTPS exfiltration without DNS/egress filtering |

---

### T6 — Infrastructure Drift / Unauthorised Change

| Attribute | Detail |
|---|---|
| **Category** | Tampering |
| **Actor** | Developer, pipeline misconfiguration |
| **Attack vector** | Manual AWS console changes, `terraform apply` from unreviewed branch |
| **Impact** | Security regression, compliance violation, outage |
| **Likelihood** | Medium |
| **Mitigations** | Terraform state locked in DynamoDB (prevents concurrent applies); `terraform plan` posted as PR comment (peer review before merge); Checkov policy gate blocks non-compliant IaC; workspace-based IAM (`TerraformRole`) limits blast radius; all resource changes must go through CI pipeline |
| **Residual risk** | Medium — no immutable infrastructure enforcement; manual console access still possible for users with `TerraformRole` |

---

### T7 — Repudiation (Audit Gap)

| Attribute | Detail |
|---|---|
| **Category** | Repudiation |
| **Actor** | Any actor making changes |
| **Attack vector** | Changes made without traceable audit trail |
| **Impact** | Inability to investigate incidents or demonstrate compliance |
| **Likelihood** | Low |
| **Mitigations** | All CI/CD actions logged in GitHub Actions audit log; Terraform apply output uploaded as artefact (30-day retention); CloudWatch Logs retain app and ECS exec logs for 365 days; ALB access logs written to S3; resource tags (`Owner`, `CostCenter`, `Terraform=True`) trace every resource to its provisioning method |
| **Residual risk** | Medium — no CloudTrail enabled; API-level audit of AWS control-plane actions is missing |

---

### T8 — Lateral Movement from Compromised Container

| Attribute | Detail |
|---|---|
| **Category** | Elevation of Privilege |
| **Actor** | Attacker who has gained code execution in ECS task |
| **Attack vector** | Use ECS task IAM role to enumerate/access other AWS services |
| **Impact** | Pivot to other services, data access beyond application scope |
| **Likelihood** | Low |
| **Mitigations** | ECS task role scoped to minimum required permissions (ECS Exec SSM channels + KMS decrypt only); execution role and task role are separate; no access to S3 state bucket from task role; private subnets with outbound HTTPS only |
| **Residual risk** | Low |

---

## Risk Summary

| ID | Threat | Likelihood | Impact | Residual Risk |
|---|---|---|---|---|
| T1 | DDoS | Medium | High | Low |
| T2 | Web application attack | Medium | High | Low |
| T3 | Supply chain / image compromise | Medium | High | Medium |
| T4 | Credential theft | Low | Critical | Low |
| T5 | Data exfiltration | Low | High | Low |
| T6 | Infrastructure drift | Medium | High | Medium |
| T7 | Audit gap / repudiation | Low | Medium | Medium |
| T8 | Lateral movement | Low | High | Low |

---

## Recommended Future Improvements

| Item | Priority |
|---|---|
| Enable AWS CloudTrail (all regions, S3 log bucket, integrity validation) | High |
| Enable VPC Flow Logs (IAM role + dedicated log group) | High |
| Add Shield Advanced for ALB DDoS protection | Medium |
| Implement DNS/egress filtering (Route53 Resolver DNS Firewall) to limit exfiltration | Medium |
| Add S3 Object Lock (WORM) to state bucket for compliance | Medium |
| Deploy NAT Gateway in both AZs for HA | Medium |
| Enable GuardDuty for threat detection | Medium |
| Add AWS Config rules for continuous compliance monitoring | Medium |
