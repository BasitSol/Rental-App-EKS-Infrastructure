# EKS Infrastructure — Complete Walkthrough

This document explains the production EKS environment built for the Rental App: what it contains, why each piece exists, how the pieces fit together, and how to operate it.

---

## 1. High-Level Architecture

```
                       ┌────────────────────────────────────────────────┐
                       │              AWS Account 664418980347          │
                       │                                                │
   Users (HTTP)        │   ┌──────────────────────────────────────┐     │
       │               │   │              Region: us-east-1       │     │
       ▼               │   │                                      │     │
 ┌──────────────┐      │   │   ┌──────────────────────────────┐   │     │
 │ Public NLB   │◀─────┼───┼───┤  VPC 10.50.0.0/16             │   │     │
 │ (Network LB) │      │   │   │                              │   │     │
 └──────┬───────┘      │   │   │   ┌────────┐  ┌────────┐  ┌──────┐│     │
        │              │   │   │   │Pub-AZa │  │Pub-AZb │  │Pub-c ││     │
        │              │   │   │   │+ IGW   │  │+ IGW   │  │+ IGW ││     │
        │ port 80      │   │   │   └────┬───┘  └───┬────┘  └──┬───┘│     │
        ▼              │   │   │        │  NAT GW per AZ        │  │     │
 ┌─────────────────┐   │   │   │   ┌────▼───┐  ┌───▼────┐  ┌──▼───┐│     │
 │ ingress-nginx   │   │   │   │   │Priv-AZa│  │Priv-AZb│  │Priv-c││     │
 │ (DaemonSet on   │   │   │   │   │        │  │        │  │      ││     │
 │ EKS nodes)      │◀──┼───┼───┼───┤        │  │        │  │      ││     │
 └────────┬────────┘   │   │   │   └────────┘  └────────┘  └──────┘│     │
          │            │   │   │       │           │          │    │     │
          ▼            │   │   │       └───────┬───┴──────────┘    │     │
   ┌──────────────┐    │   │   │               ▼                   │     │
   │ K8s Ingress  │    │   │   │       ┌──────────────────┐        │     │
   │ rental-      │    │   │   │       │  EKS Control     │        │     │
   │ ingress      │    │   │   │       │  Plane (managed) │        │     │
   └──────┬───────┘    │   │   │       └────────┬─────────┘        │     │
          │paths       │   │   │                │                  │     │
   ┌──────┴───────┐    │   │   │     ┌──────────▼───────────┐      │     │
   │              │    │   │   │     │ Managed Node Group   │      │     │
   ▼              ▼    │   │   │     │ 8 × t3.micro         │      │     │
 ┌─────┐       ┌──────┐│   │   │     │ in private subnets   │      │     │
 │ api │       │client││   │   │     └──────────────────────┘      │     │
 │svc  │       │ svc  ││   │   │                                   │     │
 └──┬──┘       └──┬───┘│   │   └───────────────────────────────────┘     │
    │             │    │   │                                              │
    ▼             ▼    │   │   ┌───────────────┐  ┌─────────────────┐    │
 ┌──────┐    ┌─────────┐│   │   │ ECR Repos     │  │ Secrets Manager │    │
 │api   │    │ client  ││   │   │ rental/api    │  │ /rentalapp/     │    │
 │pods 2│    │ pods 2  ││   │   │ rental/client │  │ eks-prod/*      │    │
 └──┬───┘    └─────────┘│   │   └───────────────┘  └────────┬────────┘    │
    │                   │   │                                │             │
    ▼                   │   │                                │ external-   │
 ┌─────────────────────┐│   │                                │ secrets     │
 │ MongoDB Atlas (SaaS)││   │                                │ (IRSA)      │
 └─────────────────────┘│   │                                │             │
                        │   └────────────────────────────────┴─────────────┘
                        └────────────────────────────────────────────────┘
```

### Layered view

| Layer | Component | Why |
|---|---|---|
| Edge | NLB (Layer-4) | Single entry point for public traffic; provisioned automatically by the `ingress-nginx` Service of type LoadBalancer |
| Ingress | ingress-nginx controller | Routes HTTP requests by path/host to internal K8s Services |
| Compute | EKS control plane + managed node group | Runs all workloads; 8 × `t3.micro` nodes (Free Tier eligible) |
| App | `api-deployment` + `client-deployment` | The Rental App backend and frontend |
| Data | MongoDB Atlas (external SaaS) | Application database; reached over the NAT Gateways via TLS |
| Secrets | AWS Secrets Manager + External Secrets Operator | Stores DB URI / session / JWT secrets and syncs them into K8s Secrets |
| Registry | ECR (`rental/api`, `rental/client`) | Container image storage |

---

## 2. Repository Layout (only the EKS bits)

```
terraform/
├── environments/
│   └── eks-production/      ← THIS environment, the one CI applies
│       ├── main.tf          ← wires modules together
│       ├── kubernetes.tf    ← Helm releases + every K8s resource
│       ├── github-oidc.tf   ← IAM role + OIDC trust for GitHub Actions
│       ├── variables.tf
│       ├── outputs.tf       ← exposes app_url, cluster_name, etc.
│       ├── providers.tf     ← AWS / Kubernetes / Helm / Kubectl providers
│       ├── backend.tf       ← S3 + DynamoDB state backend
│       ├── checks.tf        ← preflight assertions
│       └── secrets.auto.tfvars   ← (gitignored) local-only secret values
└── modules/
    ├── networking/      ← VPC, subnets, NAT, IGW, route tables
    ├── eks-cluster/     ← EKS control plane, node group, OIDC, IRSA role for ESO
    ├── app-secrets/     ← 3× aws_secretsmanager_secret with 7-day recovery
    └── github-runner/   ← (unused now) self-hosted runner ASG; CI uses GitHub-hosted
```

Everything in `kubernetes.tf` is gated by `local.k8s_enabled = var.enable_k8s_resources`. Locally the variable defaults to `false` (so you can plan infra without needing cluster access); CI sets it to `true`.

---

## 3. Module-by-Module

### 3.1 `networking` module

Creates the **VPC and traffic layout**:

- VPC CIDR: `10.50.0.0/16`
- **3 public subnets** (one per AZ: us-east-1a/b/c) — host the NAT Gateways and receive the NLB ENIs
- **3 private subnets** — host the EKS worker nodes
- **Internet Gateway** attached to the VPC; public subnets route `0.0.0.0/0 → IGW`
- **3 NAT Gateways** (one per AZ for HA) with Elastic IPs; private subnets route `0.0.0.0/0 → NAT`

This split is the standard pattern: pods never get a public IP, but they can pull images, hit MongoDB Atlas, and reach AWS APIs through the NATs.

**Outputs**: `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `nat_eip` (the 3 EIPs you must allowlist in MongoDB Atlas).

### 3.2 `eks-cluster` module

Creates the **Kubernetes substrate**:

- `aws_eks_cluster.main` — control plane, version `1.30`, endpoint open to `0.0.0.0/0` (auth still gated by IAM — see §4)
- `aws_eks_node_group.main` — managed node group: 8 × `t3.micro` in private subnets, 50 GiB EBS each
- OIDC provider (`aws_iam_openid_connect_provider`) attached to the cluster — required for IRSA (IAM Roles for Service Accounts)
- IRSA role for the External Secrets Operator (scoped to `Secrets Manager : GetSecretValue` on the `/rentalapp/eks-prod/*` prefix)
- All standard EKS node IAM policies attached: `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonEKS_CNI_Policy`

#### Why `t3.micro × 8`?

The AWS account is currently restricted to Free-Tier instance families. `t3.micro` has a **hard limit of 4 pods per node** (a VPC-CNI / ENI limit on small instances). Each node also runs 2 daemonset pods (`aws-node`, `kube-proxy`), so net usable slots are `4 − 2 = 2 per node`. With 8 nodes that's 16 slots — exactly enough to fit the full stack (see §5 for the slot math).

If/when the Free Tier restriction is lifted, switching to `t3.medium × 3` (17 pods each = 51 slots) would be a one-line change in `variables.tf`.

### 3.3 `app-secrets` module

Creates three Secrets Manager entries:

| AWS name | Holds |
|---|---|
| `/rentalapp/eks-prod/mongodb_uri` | MongoDB Atlas connection string |
| `/rentalapp/eks-prod/session_secret` | Express session signing key |
| `/rentalapp/eks-prod/jwt_secret` | JWT signing key |

All three have `recovery_window_in_days = 7` (soft-delete safety net; see §7).

The actual values come from Terraform variables (`var.mongodb_uri`, etc.) — locally from `secrets.auto.tfvars`, in CI from GitHub Secrets (`MONGODB_URI`, `SESSION_SECRET`, `JWT_SECRET`).

### 3.4 `github-oidc.tf` (not a module — lives in the environment)

This is the **IAM glue that lets GitHub Actions authenticate to AWS without static keys**:

```
GitHub Actions Job  ──assumes──▶  arn:aws:iam::664418980347:role/rentalapp-gha-deploy
        │                                       │
        │ id-token: write                        │ assumed via OIDC
        ▼                                       ▼
  OIDC token signed                Trust policy allows:
  by token.actions.                  token.actions.githubusercontent.com
  githubusercontent.com              + repo:BasitSol/Rental-App-EKS-Infrastructure:*
```

Resources:
- `aws_iam_openid_connect_provider.github` — registers GitHub's OIDC issuer in AWS IAM (one-time per account)
- `aws_iam_role.github_actions` — the role CI assumes, named `rentalapp-gha-deploy`
- `aws_iam_policy.github_actions_deploy` — the inline permission set (ECR, EC2, EKS, IAM, Secrets Manager, logs, KMS — everything needed to apply this terraform)
- `aws_eks_access_entry` + `aws_eks_access_policy_association` (in `main.tf`) — gives the same role `AmazonEKSClusterAdminPolicy` inside the EKS cluster so `kubectl` works from CI

### 3.5 `kubernetes.tf` (where everything K8s lives)

This single file owns:

| Group | Resources |
|---|---|
| Providers data | `data "aws_eks_cluster"`, `data "kubernetes_service" "ingress_nginx_controller"` (for NLB auto-discovery) |
| Helm releases | `ingress_nginx`, `cert_manager`, `metrics_server`, `external_secrets` |
| Namespace | `rental` (with PodSecurity `restricted` enforce label) |
| ConfigMap | `rental-api-config` (env vars for API; includes auto-discovered `CLIENT_URL`) |
| Deployments | `api-deployment` (2 replicas), `client-deployment` (2 replicas) |
| Services | `api-service`, `client-service` (both ClusterIP) |
| Ingress | `rental-ingress` — path-based routing: `/healthz`, `/readyz`, `/api/*` → api; `/*` → client |
| HPA | `api-hpa`, `client-hpa` — scale 2→6 based on CPU 70% / mem 75% |
| PDB | `api-pdb`, `client-pdb` — max 1 unavailable |
| NetworkPolicy | Default-deny + targeted allow rules |
| ServiceAccounts | `rental-external-secrets` (IRSA-annotated) |
| kubectl_manifest | `ClusterIssuer` (Let's Encrypt), `SecretStore`, `ExternalSecret` (CRDs from helm charts) |

Why a mix of `kubernetes_*`, `helm_release`, and `kubectl_manifest`? Because the Terraform Kubernetes provider validates CRDs at **plan time** — but the CRDs don't exist yet on a fresh cluster. `kubectl_manifest` defers validation to apply time, so it can create `ClusterIssuer`/`SecretStore`/`ExternalSecret` after the helm charts that define their CRDs have run.

---

## 4. Access Model

```
                                    ┌─────────────────────────┐
                                    │   GitHub Actions Job    │
                                    │   (OIDC token)          │
                                    └────────────┬────────────┘
                                                 │ STS:AssumeRoleWithWebIdentity
                                                 ▼
   ┌────────────────────────────────────────────────────────────────┐
   │  IAM Role: rentalapp-gha-deploy                                │
   │  Policy: ECR push/pull, EKS describe/update, EC2, IAM, KMS,    │
   │          Secrets Manager (CRUD on /rentalapp/*), logs:*        │
   └────────────────────────────┬───────────────────────────────────┘
                                │
                ┌───────────────┼─────────────────┐
                ▼               ▼                 ▼
        ECR pushes        EKS API calls     Secrets Manager
        + describe        (via Access       CRUD
                          Entry +
                          AmazonEKS
                          ClusterAdmin)
                                │
                                ▼
                  Cluster RBAC: cluster-admin
                  (so kubectl + helm work)
```

**No long-lived AWS keys exist.** Every CI run starts by minting a short-lived OIDC token, exchanging it for STS credentials via the role, and using those for ~15 minutes.

---

## 5. Pod Capacity Math (why 8 nodes)

`t3.micro` has a hard pod limit of 4 due to VPC-CNI ENI constraints. Each node already runs:

- `aws-node` (DaemonSet, VPC CNI)
- `kube-proxy` (DaemonSet)

= **2 mandatory pods per node**, leaving **2 usable slots per node**.

With 8 nodes → **16 usable slots**. The workload:

| Pod group | Pods |
|---|---|
| coredns | 2 |
| metrics-server | 1 |
| external-secrets (controller + cert-controller + webhook) | 3 |
| cert-manager (controller + cainjector + webhook) | 3 |
| ingress-nginx controller | 1 |
| api | 2 |
| client | 2 |
| HPA buffer | ~2 |
| **Total** | **~16** |

Exactly the budget. If anything new is added (Prometheus, Loki, etc.), the node count must go up.

---

## 6. Security Posture

| Layer | Hardening |
|---|---|
| Network | Workers in private subnets, no public IPs on pods. Egress goes through NAT. |
| EKS API | Endpoint public (so CI can reach it) but auth gated by IAM Access Entries. No service token mounted unless explicitly needed. |
| Pods | Namespace `rental` enforces PodSecurity `restricted`: `runAsNonRoot=true`, `runAsUser=10001/101`, `readOnlyRootFilesystem=true`, `allowPrivilegeEscalation=false`, all capabilities dropped, `seccompProfile=RuntimeDefault`. |
| Secrets | Stored in AWS Secrets Manager, never in env vars or git. Pulled into K8s by the External Secrets Operator using IRSA (no static AWS keys in pods). |
| Image supply | CI tags images with the commit SHA, then resolves to immutable image digests (`@sha256:...`) before passing them to Terraform. Pods always reference digests, not tags. |
| NetworkPolicy | Default-deny ingress; explicit allow rules for ingress-nginx → api/client. |
| CI identity | GitHub OIDC federated to a single IAM role. No static AWS keys exist. |

---

## 7. Lifecycle: Stand-up, Update, Tear-down

### 7.1 First-time stand-up

1. Create the S3 bucket + DynamoDB lock table for Terraform state (one-time, manual).
2. Push initial commit to `main` → `deploy.yml` runs.
3. ~15-25 minutes later: cluster, helm releases, deployments, NLB are all up.
4. Get the URL: `terraform output app_url` (or read the ingress-nginx service hostname).

### 7.2 Day-to-day changes

- Code change in `api-staging/` or `client-staging/` → push → CI builds new image, resolves to digest, runs `terraform apply` → rolling update with zero downtime (max-surge 1, max-unavailable 0).
- Infra change in `terraform/...` → ideally via PR (so `pr-validation.yml` plans it first) → merge → CI applies.

### 7.3 Tear-down

Manual workflow (`destroy.yml`):
1. Open Actions → "Destroy EKS" → Run workflow
2. Type `DESTROY` in the confirmation field
3. CI does a K8s pre-cleanup (deletes the ingress-nginx Service so AWS reaps the NLB, uninstalls helm releases) — this prevents the famous "VPC has dependent objects" stall during destroy
4. `terraform destroy` runs

**What survives destroy:**
- ECR repositories and all images (not in this Terraform state)
- Secrets Manager entries (soft-deleted with 7-day recovery window; auto-restored on next deploy — see CICD.md §6)
- S3 state bucket / DynamoDB lock table

### 7.4 Recreate within 7 days

Just push to main. `deploy.yml`'s "Restore scheduled-for-deletion secrets" step finds the soft-deleted secrets, restores them, re-imports into state. Terraform sees them as already-managed and `apply` proceeds normally. **No manual steps.**

---

## 8. Critical Configuration Knobs

In `terraform/environments/eks-production/variables.tf`:

| Variable | Default | What it controls |
|---|---|---|
| `node_instance_types` | `["t3.micro"]` | Worker EC2 family. Switch when Free Tier restriction lifts. |
| `node_min_size` / `desired_size` / `max_size` | `8 / 8 / 10` | Node group scaling. |
| `cluster_endpoint_public_access_cidrs` | `["0.0.0.0/0"]` | Who can reach the EKS API. Tighten to your office + GitHub Actions IP ranges for prod. |
| `ingress_host` | `""` (auto-discover) | Set to a custom domain when you have one CNAME'd to the NLB. |
| `enable_k8s_resources` | `false` | Off locally (just infra), `true` in CI. |
| `external_secrets_enabled` | `true` | Whether to create the IRSA role for ESO. |

In `terraform/environments/eks-production/github-oidc.tf` — the IAM policy is intentionally broad (deploy role needs to create/destroy almost anything). Worth tightening for true prod.

---

## 9. Observability (current state + gaps)

**Today:**
- `metrics-server` is installed → `kubectl top pods/nodes` works, HPAs scale based on it.
- CloudWatch Logs: EKS control plane logging is **not** enabled (cost — easy to turn on if you want audit/api/scheduler logs).
- App logs: stdout of pods, viewable via `kubectl logs` only. Not shipped anywhere.

**Recommended next steps:**
- Enable EKS control-plane logging (`api`, `audit`, `authenticator`).
- Install a log aggregator (Loki + Promtail, or ship to CloudWatch via Fluent Bit).
- Install kube-prometheus-stack for metrics + alerts.

---

## 10. Cost Snapshot (us-east-1, on-demand, monthly)

| Item | ~Cost |
|---|---|
| EKS control plane | $73 |
| 8 × t3.micro EC2 | ~$70 (750h Free Tier covers ~1 node, remaining 7 billed) |
| 3 × NAT Gateway (hourly + GB processing) | ~$100 |
| NLB | ~$20 + data processing |
| EBS (8 × 50 GiB gp3) | ~$32 |
| Secrets Manager (3 secrets) | ~$1.20 |
| ECR storage | ~$1-2 |
| **Total** | **~$300/month** |

The 3-AZ NAT Gateways are the biggest line item. For non-prod, drop to 1 NAT (single-AZ) and save ~$66/month.

---

## 11. Failure Recovery Playbook

| Symptom | Likely cause | Action |
|---|---|---|
| Pod stays `Pending` | No node capacity (pod-per-node limit hit) | Check `kubectl describe pod` → "Insufficient pods"; bump `node_desired_size` |
| `bad auth` on MongoDB | Atlas password rotated or IP not allowlisted | Check Atlas Database Access; ensure NAT EIPs are in Network Access list |
| Ingress returns 404 | Ingress `host:` doesn't match URL | Confirm `var.ingress_host` is empty (auto-discover) or matches the URL you're hitting |
| Helm release timeout (NLB) | NLB provisioning slow | Already mitigated: `timeout = 1200`, `atomic = false` on ingress-nginx |
| `kubectl` from CI fails with 403 | Access Entry missing | Verify `aws_eks_access_entry.github_actions` exists |
| Terraform "scheduled for deletion" | Recreating within 7 days of destroy | deploy.yml handles it automatically; if running locally, `aws secretsmanager restore-secret` then `terraform import` |

---

## 12. Outputs Reference

After `terraform apply` (or `terraform output` later):

```bash
terraform output app_url                # http://<NLB>.us-east-1.elb.amazonaws.com
terraform output cluster_name           # rentalapp-eks-prod-eks
terraform output kubectl_config_command # aws eks update-kubeconfig ...
terraform output nat_eip                # 3 IPs to allowlist in MongoDB Atlas
terraform output github_actions_role_arn # for GitHub repo secret AWS_ROLE_ARN
```

---

## 13. Glossary

| Term | Meaning |
|---|---|
| **EKS** | Elastic Kubernetes Service — AWS managed Kubernetes control plane |
| **NLB** | Network Load Balancer — Layer 4 AWS load balancer |
| **IRSA** | IAM Roles for Service Accounts — lets a K8s pod assume an AWS IAM role using its ServiceAccount token |
| **OIDC** | OpenID Connect — token-based federated identity (GitHub → AWS here) |
| **PSS** | Pod Security Standards — built-in K8s pod hardening profiles (`privileged` / `baseline` / `restricted`) |
| **HPA / PDB** | Horizontal Pod Autoscaler / Pod Disruption Budget |
| **ESO** | External Secrets Operator — syncs AWS Secrets Manager → K8s Secrets |
| **CRD** | Custom Resource Definition — K8s mechanism for adding new resource types |
| **CNI** | Container Network Interface — pluggable pod networking (AWS VPC CNI here) |
