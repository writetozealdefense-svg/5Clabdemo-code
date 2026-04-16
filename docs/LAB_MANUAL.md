# 5C Security Lab - Lab Manual

> **FOR EDUCATIONAL AND AUTHORIZED SECURITY TRAINING ONLY**

## Lab Environment

- **Platform**: Google Cloud Platform (GKE, GCS, Vertex AI)
- **Region**: us-central1
- **App URL**: `http://<NODE_IP>:30080`
- **Compliance Frameworks**: SAMA-CSF, NCA-ECC, NCA-CCC, PDPL

## Getting Started

```bash
# Get your Node IP
export NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
echo "App URL: http://$NODE_IP:30080"
```

## Lab Index

### Part 1: Intra-Layer Labs

These labs explore vulnerabilities within a single layer.

| Lab | Title | Layer | Difficulty | Duration | OWASP | Prerequisites |
|-----|-------|-------|------------|----------|-------|---------------|
| [01](../labs/lab01-code-injection.md) | Code Injection & SSRF | Code | Beginner | 30 min | A03, A10 | Deployed environment |
| [02](../labs/lab02-container-misconfig.md) | Container Misconfiguration | Container | Beginner | 25 min | A05, A06 | Deployed environment |
| [03](../labs/lab03-cluster-exploitation.md) | Cluster Exploitation | Cluster | Intermediate | 40 min | A01, A05, A07 | Deployed environment |
| [04](../labs/lab04-cloud-escalation.md) | Cloud Privilege Escalation | Cloud | Intermediate | 40 min | A01, A02, A10 | Deployed environment |
| [05](../labs/lab05-ai-prompt-injection.md) | AI Prompt Injection | AI | Intermediate | 35 min | A03, A04 | Deployed environment |

### Part 2: Cross-Layer Pivot Labs

These labs demonstrate how attackers chain vulnerabilities to pivot between layers.

| Lab | Title | Pivot | Difficulty | Duration | Prerequisites |
|-----|-------|-------|------------|----------|---------------|
| [06](../labs/lab06-code-to-container.md) | Code to Container | Code → Container | Intermediate | 30 min | Lab 01 |
| [07](../labs/lab07-container-to-cluster.md) | Container to Cluster | Container → Cluster | Advanced | 40 min | Lab 02 |
| [08](../labs/lab08-cluster-to-cloud.md) | Cluster to Cloud | Cluster → Cloud | Advanced | 40 min | Lab 03 or 07 |
| [09](../labs/lab09-cloud-to-ai.md) | Cloud to AI | Cloud → AI | Advanced | 35 min | Lab 04 or 08 |
| [10](../labs/lab10-ai-to-code.md) | AI to Code | AI → Code | Advanced | 35 min | Lab 05 |

### Part 3: Full Chain Lab

| Lab | Title | Scope | Difficulty | Duration | Prerequisites |
|-----|-------|-------|------------|----------|---------------|
| [11](../labs/lab11-full-attack-chain.md) | Full Attack Chain | All 5 Layers | Expert | 90 min | Labs 01-10 (conceptual familiarity) |

## Recommended Lab Order

### Track A: Layer-by-Layer (Recommended for beginners)
```
Lab 01 → Lab 02 → Lab 03 → Lab 04 → Lab 05 → Lab 11
```

### Track B: Attack Chain Focus (Recommended for intermediate)
```
Lab 01 → Lab 06 → Lab 07 → Lab 08 → Lab 09 → Lab 10 → Lab 11
```

### Track C: Full Course (Recommended for comprehensive training)
```
Lab 01 → Lab 02 → Lab 06 → Lab 03 → Lab 07 → Lab 04 → Lab 08 → Lab 05 → Lab 09 → Lab 10 → Lab 11
```

## GCC Compliance Mapping

| Lab | SAMA-CSF | NCA-ECC | NCA-CCC | PDPL |
|-----|----------|---------|---------|------|
| 01 | 3.1.2, 3.1.4 | 1-3-1, 2-6-1 | - | - |
| 02 | 3.3.2, 3.3.6 | 2-3-1, 2-3-2 | - | - |
| 03 | 3.2.1, 3.2.4 | 1-1-3, 2-2-1, 2-6-1 | - | - |
| 04 | 3.2.1, 3.3.4, 3.3.5 | - | 2-1-4, 2-2-1 | - |
| 05 | 3.1.2, 3.1.3 | 1-1-3, 2-6-1 | - | Art. 9, 12, 19 |
| 06 | 3.1.2 + 3.3.2 | 2-4-1 | - | - |
| 07 | - | 1-1-3, 2-3-1, 2-3-2 | - | - |
| 08 | 3.2.1, 3.2.2 | - | 2-1-4 | - |
| 09 | - | 2-3-3 | - | Art. 9, 12, 14 |
| 10 | 3.1.2 | 1-1-2, 1-1-3 | - | Art. 19 |
| 11 | All above | All above | All above | All above |

## Cleanup

After completing all labs:

```bash
./scripts/cleanup.sh
```
