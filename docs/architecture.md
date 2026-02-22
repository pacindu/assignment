# Architecture — NTT GCC Assignment 1

## Overview

A secure, compliant AWS landing zone running a containerised Python microservice on ECS Fargate,
exposed through an Application Load Balancer with TLS termination, protected by AWS WAF, and
deployed via a fully automated GitHub Actions CI/CD pipeline.

**Region:** ap-southeast-1 (Singapore)
**Availability Zones:** ap-southeast-1a, ap-southeast-1b

---

## Architecture Diagram

```
                          Internet
                             │
                    ┌────────▼────────┐
                    │   AWS WAF v2    │  IP reputation, OWASP core,
                    │   (Regional)    │  known bad inputs, rate limit
                    └────────┬────────┘
                             │ HTTPS (443) / HTTP (301→HTTPS)
                    ┌────────▼────────┐
                    │  Application    │  TLS termination (ACM),
                    │  Load Balancer  │  access logs → S3,
                    │  (Public ALB)   │  deletion protection enabled
                    └────────┬────────┘
                             │ HTTP (container port) — internal only
              ┌──────────────┼──────────────┐
              │                             │
   ┌──────────▼──────────┐   ┌─────────────▼──────────┐
   │  ECS Fargate Task   │   │  ECS Fargate Task       │
   │  (AZ: 1a)           │   │  (AZ: 1b)               │
   │  Private Subnet     │   │  Private Subnet          │
   │  10.0.11.0/24       │   │  10.0.12.0/24            │
   └──────────┬──────────┘   └─────────────┬───────────┘
              │                             │
              └──────────────┬──────────────┘
                             │ HTTPS (443) egress only
                    ┌────────▼────────┐
                    │   NAT Gateway   │  Outbound-only internet
                    │  (Public Subnet)│  access for ECR pulls,
                    └────────┬────────┘  CloudWatch Logs
                             │
                         Internet
```

### VPC Layout — 10.0.0.0/16

```
┌─────────────────────────────────────────────────────────────────┐
│  VPC: 10.0.0.0/16                                               │
│                                                                 │
│  ┌──────────────────────┐   ┌──────────────────────┐           │
│  │  PUBLIC TIER          │   │  PUBLIC TIER          │          │
│  │  10.0.1.0/24 (AZ-1a) │   │  10.0.2.0/24 (AZ-1b) │          │
│  │  ALB, NAT Gateway    │   │  ALB (multi-AZ)       │          │
│  └──────────────────────┘   └──────────────────────┘           │
│                                                                 │
│  ┌──────────────────────┐   ┌──────────────────────┐           │
│  │  PRIVATE TIER         │   │  PRIVATE TIER         │          │
│  │  10.0.11.0/24 (AZ-1a)│   │  10.0.12.0/24 (AZ-1b)│          │
│  │  ECS Fargate tasks   │   │  ECS Fargate tasks    │          │
│  └──────────────────────┘   └──────────────────────┘           │
│                                                                 │
│  ┌──────────────────────┐   ┌──────────────────────┐           │
│  │  SECURE TIER          │   │  SECURE TIER          │          │
│  │  10.0.21.0/24 (AZ-1a)│   │  10.0.22.0/24 (AZ-1b)│          │
│  │  Reserved (databases)│   │  Reserved (databases) │          │
│  └──────────────────────┘   └──────────────────────┘           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## CI/CD Pipeline

```
┌─────────────┐     ┌──────────────────────────────────────────────────────┐
│  Developer  │────▶│  GitHub Actions — App Pipeline (app.yml)             │
│  Push / PR  │     │                                                      │
└─────────────┘     │  ┌──────┐   ┌────────────────────┐   ┌──────────┐  │
                    │  │ test │──▶│ build-scan-push     │──▶│  deploy  │  │
                    │  │pytest│   │ Trivy CVE scan       │   │  ECS     │  │
                    │  │18 tcs│   │ ECR push (:sha+latest)│  │ rolling  │  │
                    │  └──────┘   └────────────────────┘   └──────────┘  │
                    └──────────────────────────────────────────────────────┘

┌─────────────┐     ┌──────────────────────────────────────────────────────┐
│  Infra      │────▶│  GitHub Actions — Infra Pipeline (infra.yml)         │
│  Push / PR  │     │                                                      │
└─────────────┘     │  ┌──────────┐  ┌─────────┐  ┌──────┐  ┌─────────┐ │
                    │  │ validate │  │ checkov │  │ plan │  │  apply  │ │
                    │  │ fmt+lint │  │ policy  │  │ PR   │  │  main   │ │
                    │  │ tflint   │  │ gate    │  │ only │  │  push   │ │
                    │  └──────────┘  └─────────┘  └──────┘  └─────────┘ │
                    └──────────────────────────────────────────────────────┘
```

---

## Component Descriptions

### Networking

| Component | Description |
|---|---|
| VPC (10.0.0.0/16) | Isolated network boundary; DNS hostnames enabled |
| Internet Gateway | Inbound/outbound internet for public tier |
| NAT Gateway | Outbound-only internet for private tier (ECR pull, CloudWatch) |
| Route Tables | Public → IGW; Private → NAT; Secure → local only |
| Network ACLs | Stateless second layer; public NACL allows 80/443/ephemeral inbound |
| Default SG | Explicitly restricted (no ingress/egress) to prevent accidental exposure |

### Security

| Component | Description |
|---|---|
| WAF v2 | IP reputation list, OWASP core rules, known bad inputs, 2000 req/5min rate limit |
| Security Groups | ALB SG: 80/443 from 0.0.0.0/0; ECS SG: container port from ALB only |
| ACM Certificate | TLS for app.ntt.demodevops.net + wildcard; DNS auto-validated via Route53 |
| KMS Keys | CMKs for S3 state, ECS/ECR/CloudWatch Logs, SNS — 30-day deletion window |
| ALB | `drop_invalid_header_fields = true`; deletion protection enabled |
| HTTP Headers | HSTS, CSP, X-Frame-Options, X-Content-Type-Options (applied in app layer) |

### Compute

| Component | Description |
|---|---|
| ECS Cluster | Container Insights enabled; ECS Exec encrypted via KMS |
| Task Definition | arm64, 256 CPU units, 512 MB — execution + task roles separate |
| ECS Service | Desired count: 1–2; FARGATE_SPOT (weight 3) + FARGATE (weight 1, base 1) |
| Auto Scaling | CPU target 50%, memory target 50%; min 1, max 2 tasks |
| Rolling Deploy | Deployment circuit breaker with auto-rollback on health check failure |

### Observability

| Component | Description |
|---|---|
| CloudWatch Log Groups | `/ecs/exec/*`, `/ecs/app/*` — 365-day retention, KMS-encrypted |
| CPU Alarm | Triggers at 75% sustained — SNS notification |
| Memory Alarm | Triggers at 75% sustained — SNS notification |
| 5xx Alarm | Triggers at 5 errors/min on ALB — SNS notification |
| Error Log Alarm | Metric filter on `ERROR` in app logs — SNS notification |
| ALB Access Logs | Written to S3 bucket with lifecycle cleanup (365-day expiry) |

### State Management

| Component | Description |
|---|---|
| S3 State Bucket | Versioned, KMS-encrypted, public access blocked, deny-non-HTTPS policy |
| DynamoDB Lock Table | `PAY_PER_REQUEST`, KMS-encrypted, PITR enabled |
| KMS State Key | Dedicated CMK; root admin access only; 30-day deletion window |

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| ECS Fargate over EKS | Lower operational overhead; no node management; sufficient for this workload scale |
| arm64 (Graviton) | ~20% lower cost than x86_64 for equivalent performance on Fargate |
| FARGATE_SPOT primary | ~70% cost reduction vs on-demand; FARGATE base=1 ensures availability |
| Single NAT Gateway | Cost-optimised for this assignment; production HA would use one per AZ |
| Workspace-based IAM | Separate IAM roles per workspace (Production/Staging) via `assume_role` |
| Checkov policy gate | Automated compliance scanning on every push; SARIF output to GitHub Security |
| Trivy image scanning | Blocks on CRITICAL/HIGH unfixed CVEs before ECR push |
