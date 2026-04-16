# 5C Security Lab - Cloud-Native AI Governance Platform

> **FOR EDUCATIONAL AND AUTHORIZED SECURITY TRAINING ONLY**
>
> This project contains **intentionally vulnerable** infrastructure, application code,
> and AI configurations designed for hands-on security training in a controlled lab
> environment. **DO NOT** deploy this in production or on any system containing real data.
> All PII data is synthetic.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        5C SECURITY LAB ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐    ┌──────────────────┐    ┌──────────────────────────┐   │
│  │  CODE LAYER │    │  CONTAINER LAYER │    │     CLUSTER LAYER        │   │
│  │             │    │                  │    │                          │   │
│  │ Flask API   │───▶│ Docker (root,    │───▶│ GKE (privileged pods,   │   │
│  │ (SQLi, CMDi,│    │ nmap, secrets    │    │ wildcard RBAC, no       │   │
│  │  SSRF, LFI) │    │ in ENV, latest)  │    │ NetworkPolicy, ABAC)    │   │
│  └─────────────┘    └──────────────────┘    └────────────┬─────────────┘   │
│        ▲                                                  │                │
│        │            ┌──────────────────┐                  ▼                │
│        │            │    AI LAYER      │    ┌──────────────────────────┐   │
│        └────────────│                  │◀───│     CLOUD LAYER          │   │
│   (prompt injection │ Vertex AI Gemini │    │                          │   │
│    ─▶ tool calls)   │ (no guardrails,  │    │ GCP (over-provisioned    │   │
│                     │  PII in context, │    │ IAM, public GCS, legacy  │   │
│                     │  RAG poisoning)  │    │ metadata, no logging)    │   │
│                     └──────────────────┘    └──────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| Google Cloud SDK (`gcloud`) | 450+ | GCP authentication and API management |
| Terraform | 1.5+ | Infrastructure as Code deployment |
| kubectl | 1.28+ | Kubernetes cluster management |
| Docker | 24+ | Container image building |
| Python | 3.11+ | Local development and testing |
| `curl` | any | Lab exercise execution |

## Quick Start

```bash
# 1. Clone and configure
git clone <repo-url> && cd 5Clabdemo-code
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform/terraform.tfvars with your GCP project ID

# 2. Setup and deploy
chmod +x scripts/*.sh
./scripts/setup.sh
./scripts/deploy.sh

# 3. Start labs
# Open docs/LAB_MANUAL.md for the full lab index
```

See [docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md) for detailed deployment instructions.

## Lab Index

### Intra-Layer Labs

| Lab | Title | Layer | Difficulty | OWASP |
|-----|-------|-------|------------|-------|
| [01](labs/lab01-code-injection.md) | Code Injection & SSRF | Code | Beginner | A03, A10 |
| [02](labs/lab02-container-misconfig.md) | Container Misconfiguration | Container | Beginner | A05, A06 |
| [03](labs/lab03-cluster-exploitation.md) | Cluster Exploitation | Cluster | Intermediate | A01, A05 |
| [04](labs/lab04-cloud-escalation.md) | Cloud Privilege Escalation | Cloud | Intermediate | A01, A05, A10 |
| [05](labs/lab05-ai-prompt-injection.md) | AI Prompt Injection | AI | Intermediate | A03, A04 |

### Cross-Layer Pivot Labs

| Lab | Title | Pivot | Difficulty | OWASP |
|-----|-------|-------|------------|-------|
| [06](labs/lab06-code-to-container.md) | Code to Container | Code → Container | Intermediate | A03, A05 |
| [07](labs/lab07-container-to-cluster.md) | Container to Cluster | Container → Cluster | Advanced | A01, A05 |
| [08](labs/lab08-cluster-to-cloud.md) | Cluster to Cloud | Cluster → Cloud | Advanced | A01, A10 |
| [09](labs/lab09-cloud-to-ai.md) | Cloud to AI | Cloud → AI | Advanced | A01, A08 |
| [10](labs/lab10-ai-to-code.md) | AI to Code | AI → Code | Advanced | A03, A04 |

### Full Chain Lab

| Lab | Title | Scope | Difficulty |
|-----|-------|-------|------------|
| [11](labs/lab11-full-attack-chain.md) | Full Attack Chain | All 5 Layers | Expert |

## GCC Compliance Mapping

| Framework | Controls Violated | Layers |
|-----------|-------------------|--------|
| **SAMA-CSF** | 3.1.2, 3.1.3, 3.1.4, 3.2.1, 3.2.2, 3.2.3, 3.2.4, 3.3.2, 3.3.3, 3.3.4, 3.3.5, 3.3.6 | All |
| **NCA-ECC** | 1-1-1, 1-1-2, 1-1-3, 1-3-1, 2-2-1, 2-3-1, 2-3-2, 2-3-3, 2-4-1, 2-6-1, 2-6-2 | All |
| **NCA-CCC** | 1-2-1, 2-1-4, 2-2-1, 2-2-3 | Cloud, Cluster |
| **PDPL** | Art. 9, Art. 12, Art. 14, Art. 19 | AI, Cloud |

## Cleanup

```bash
./scripts/cleanup.sh
```

This destroys all GCP resources, deletes container images, and cleans local state.

## Estimated Cost

- **GKE cluster (2x e2-standard-4)**: ~$4.80/day
- **GCS storage**: < $0.01/day
- **Vertex AI (Gemini Flash)**: ~$0.01-0.10/day (per lab usage)
- **Total**: ~$5-10/day

**Run `scripts/cleanup.sh` immediately after completing labs to avoid charges.**

## License

This project is provided for educational and authorized security training purposes only.
Use of this software for unauthorized access to systems you do not own is prohibited.
