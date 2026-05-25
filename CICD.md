# CI/CD Pipeline — How It Works End to End

This document explains the three GitHub Actions workflows that drive the Rental App's EKS environment: when they trigger, what they do, how they integrate, and why each step exists.

> Companion document: `INFRASTRUCTURE.md` for the EKS infrastructure they target.

---

## 1. The Three Workflows at a Glance

| Workflow | File | Trigger | What it does | Touches AWS? |
|---|---|---|---|---|
| **Deploy** | `.github/workflows/deploy.yml` | `push` to `main` (auto) + manual `workflow_dispatch` | Build images → restore secrets if needed → plan → apply → verify rollout | Yes (apply) |
| **PR Validation** | `.github/workflows/pr-validation.yml` | `pull_request` to `main` (path-filtered) | fmt → init → validate → plan → comment plan on PR | Read-only (plan) |
| **Destroy** | `.github/workflows/destroy.yml` | Manual only, requires typing `DESTROY` | K8s pre-cleanup → terraform destroy | Yes (destroy) |

```
                ┌─────────────────────────────────────────────────────┐
                │                  Developer Loop                     │
                └─────────────────────────────────────────────────────┘

   feature branch    open PR        pr-validation.yml
       ────────▶  ─────────────▶  ┌────────────────────┐
                                  │ fmt + init +       │
                                  │ validate + plan    │──▶ comment on PR
                                  └────────────────────┘
                                          │
                                  reviewer approves
                                          │
                                          ▼
                                    merge to main
                                          │
                                          ▼
                                  deploy.yml (auto)
                                  ┌────────────────────┐
                                  │ build → push ECR   │
                                  │ restore secrets    │
                                  │ plan → apply       │
                                  │ verify rollout     │
                                  └────────────────────┘
                                          │
                                          ▼
                                   prod cluster live


                ┌─────────────────────────────────────────────────────┐
                │             Operator Loop (when needed)             │
                └─────────────────────────────────────────────────────┘

   Actions tab  ─▶  Destroy EKS  ─▶  type "DESTROY"  ─▶  destroy.yml
                                                       ┌────────────────────┐
                                                       │ K8s pre-cleanup    │
                                                       │ terraform destroy  │
                                                       └────────────────────┘
```

---

## 2. Authentication — One Identity, Zero Static Keys

All three workflows authenticate to AWS the same way: **GitHub OIDC**.

```
┌─────────────────────────────────┐
│ GitHub Actions Job              │
│                                 │
│ permissions:                    │
│   id-token: write               │  ◀── lets the job mint an OIDC token
│   contents: read                │
└──────────────┬──────────────────┘
               │
               │ 1. Mint signed OIDC token
               │    (issuer: token.actions.githubusercontent.com)
               │    (sub: repo:BasitSol/Rental-App-EKS-Infrastructure:...)
               ▼
┌─────────────────────────────────────────────────────────┐
│ Step: aws-actions/configure-aws-credentials@v4          │
│   role-to-assume: ${{ secrets.AWS_ROLE_ARN }}           │
└──────────────┬──────────────────────────────────────────┘
               │
               │ 2. STS AssumeRoleWithWebIdentity(token)
               ▼
┌─────────────────────────────────────────────────────────┐
│ AWS STS — validates token signature + audience + sub    │
│ against the trust policy of role rentalapp-gha-deploy   │
└──────────────┬──────────────────────────────────────────┘
               │
               │ 3. Returns short-lived (1h) access keys
               ▼
┌─────────────────────────────────────────────────────────┐
│ Env vars in job: AWS_ACCESS_KEY_ID,                     │
│                  AWS_SECRET_ACCESS_KEY,                 │
│                  AWS_SESSION_TOKEN                      │
│ Used by every subsequent step (aws CLI, terraform,      │
│ helm via aws eks get-token, kubectl, docker push, ...)  │
└─────────────────────────────────────────────────────────┘
```

**Required GitHub repo configuration:**
- Repo secret `AWS_ROLE_ARN` = `arn:aws:iam::664418980347:role/rentalapp-gha-deploy`
- Repo secrets `MONGODB_URI`, `SESSION_SECRET`, `JWT_SECRET` — passed to Terraform as `TF_VAR_*`

No PATs, no long-lived AWS access keys, no key rotation. The trust policy on the IAM role specifies exactly which repo + branch ref can assume it.

---

## 3. `deploy.yml` — Step-by-Step

**File:** `.github/workflows/deploy.yml`
**Runs on:** push to `main`, or manual dispatch
**Runtime:** ~5 min for a code-only change; ~20-25 min for a from-zero infra build

```
┌─────────────────────────────────────────────────────────────┐
│ Job: Build, Plan & Deploy                                   │
│ Runner: ubuntu-latest (GitHub-hosted)                       │
└─────────────────────────────────────────────────────────────┘
   │
   ├─[1]─ Checkout
   │      └ git clone the repo at the pushed SHA
   │
   ├─[2]─ Configure AWS credentials  (OIDC, see §2)
   │
   ├─[3]─ Login to Amazon ECR
   │      └ aws ecr get-login-password → docker login
   │
   ├─[4]─ Set up Docker Buildx
   │      └ enables multi-platform builds + cache backends
   │
   ├─[5]─ Build and push API image
   │      ├ context: ./api-staging
   │      ├ tag:     <ecr>/rental/api:<commit-sha>
   │      └ cache:   GitHub Actions cache (scope=api-staging)
   │
   ├─[6]─ Build and push Client image
   │      ├ context: ./client-staging
   │      ├ tag:     <ecr>/rental/client:<commit-sha>
   │      └ cache:   GitHub Actions cache (scope=client-staging)
   │
   ├─[7]─ Resolve image digests
   │      ├ aws ecr describe-images → grab the sha256 digest
   │      └ outputs: api_image=<ecr>/rental/api@sha256:...
   │                 client_image=<ecr>/rental/client@sha256:...
   │      (immutable references — pods can't be silently swapped)
   │
   ├─[8]─ Setup Terraform 1.6.6
   │
   ├─[9]─ Terraform init
   │      └ pulls providers, configures S3 backend, acquires DynamoDB lock
   │
   ├─[10]─ Restore scheduled-for-deletion secrets   (see §6)
   │       └ if previous destroy left secrets in 7-day recovery,
   │         restore them and re-import into Terraform state
   │
   ├─[11]─ Terraform plan
   │       TF_VAR_mongodb_uri/session_secret/jwt_secret  ← repo secrets
   │       TF_VAR_api_image/client_image                  ← digests from step 7
   │       TF_VAR_enable_k8s_resources=true               ← (env-level)
   │       Writes to tfplan
   │
   ├─[12]─ Show plan   (so the job log has the diff for audit)
   │
   ├─[13]─ Terraform apply   (only on push or auto_approve=true)
   │       └ applies tfplan → reconciles cluster + helm + deployments
   │
   ├─[14]─ Setup kubectl 1.30
   │
   └─[15]─ Verify deployment
           ├ aws eks update-kubeconfig
           ├ kubectl rollout status deploy/api-deployment    (5min timeout)
           └ kubectl rollout status deploy/client-deployment (5min timeout)
```

### Why the immutable image digest dance (step 7)?

If we used `:<sha>` tags directly in the K8s Deployment, someone could `docker push` a different image with the same tag and pods would silently pick it up on next restart. Resolving to `@sha256:...` and pinning Deployments to digests means **the exact bits running in production are auditable from git history alone**.

### Idempotency

Re-running `deploy.yml` on the same commit is a no-op:
- Docker buildx uses GitHub cache → "no changes" → push is fast (just layer existence check).
- Digest is identical.
- `terraform plan` shows no changes.
- `terraform apply` does nothing.
- Rollout status returns immediately (no new ReplicaSet).

---

## 4. `pr-validation.yml` — Plan Before You Merge

**File:** `.github/workflows/pr-validation.yml`
**Runs on:** every `pull_request` to `main`, only when changes touch:
- `terraform/**`
- `api-staging/**`
- `client-staging/**`
- `.github/workflows/**`

**Runtime:** ~1-2 min.
**What it never does:** `terraform apply`. It is read-only.

```
┌─────────────────────────────────────────────────────────────┐
│ Job: Lint, Validate & Plan                                  │
└─────────────────────────────────────────────────────────────┘
   │
   ├─[1]─ Checkout
   ├─[2]─ Configure AWS credentials (OIDC)
   ├─[3]─ Setup Terraform 1.6.6
   │
   ├─[4]─ Terraform fmt -check -recursive
   │      └ continue-on-error: true (informational; doesn't fail PR)
   │
   ├─[5]─ Terraform init
   │
   ├─[6]─ Terraform validate
   │      └ syntax + ref checks across all .tf files
   │
   ├─[7]─ Terraform plan
   │      ├ continue-on-error: true (we want to comment even on failure)
   │      ├ captures full output to plan_output.txt
   │      └ stores exit code in env.PLAN_EXIT
   │
   ├─[8]─ Comment plan on PR   (actions/github-script)
   │      └ Posts a comment containing:
   │           - status table (fmt / init / validate / plan ✅/❌)
   │           - last 60 KB of plan output in a <details> block
   │           - actor + commit SHA
   │
   └─[9]─ Fail if plan errored
          └ if PLAN_EXIT != 0, exit 1 so the PR check goes red
```

### Why path filters?

Without them, every README typo would trigger a 2-minute plan job and post a (no-op) plan as a PR comment. Restricting to actual code paths keeps reviews focused.

### Example PR comment (truncated)

```
### Terraform PR Validation

| Check    | Result |
|----------|--------|
| Format   | ✅     |
| Init     | ✅     |
| Validate | ✅     |
| Plan     | ✅     |

<details><summary>Show Plan</summary>

  # kubernetes_deployment.api[0] will be updated in-place
  ~ spec {
      ~ template {
          ~ spec {
              ~ container {
                  ~ image = "...:abc123" → "...:def456"
                }
            }
        }
    }

Plan: 0 to add, 1 to change, 0 to destroy.
</details>

*Pushed by @basit, commit deadbeef*
```

### Why "comment on PR" instead of just CI status?

Reviewers need to **see exactly what infra changes** a code merge will cause. A green check tells you "it parses". The plan tells you "merging this will delete the EKS cluster".

---

## 5. `destroy.yml` — Controlled Teardown

**File:** `.github/workflows/destroy.yml`
**Runs on:** Manual `workflow_dispatch` ONLY.
**Inputs:**
- `confirm` (string, required): must be exactly `DESTROY` — anything else fails the job immediately
- `skip_k8s` (boolean, default `false`): use only when the cluster is already gone and you just need to drop the AWS resources

**Runtime:** ~10-15 min.

```
┌─────────────────────────────────────────────────────────────┐
│ Job: Terraform Destroy                                      │
└─────────────────────────────────────────────────────────────┘
   │
   ├─[1]─ Verify confirmation
   │      └ if inputs.confirm != "DESTROY": exit 1 immediately
   │       (zero side effects if you typed the wrong thing)
   │
   ├─[2]─ Checkout
   ├─[3]─ Configure AWS credentials (OIDC)
   ├─[4]─ Setup Terraform 1.6.6
   ├─[5]─ Terraform init
   │
   ├─[6]─ Pre-destroy K8s cleanup   (if !skip_k8s)
   │      ├ continue-on-error: true (best-effort)
   │      ├ aws eks update-kubeconfig
   │      ├ kubectl delete svc -n ingress-nginx ingress-nginx-controller
   │      │   └ frees the NLB before VPC tries to destroy itself
   │      ├ helm uninstall ingress-nginx -n ingress-nginx
   │      └ helm uninstall cert-manager -n cert-manager
   │           └ removes finalizers that would otherwise block destroy
   │
   ├─[7]─ Terraform destroy
   │      └ destroys everything in state: EKS, node group, VPC, NAT,
   │        EIPs, IAM roles, helm releases, K8s resources, Secrets
   │        Manager (soft-deleted with 7-day recovery)
   │
   └─[8]─ Summary
          └ Appends a short summary to the GitHub Actions UI
```

### Why the K8s pre-cleanup?

The most common destroy failure on EKS is: VPC won't delete because the ingress-nginx `LoadBalancer` Service is still holding an NLB, and the NLB is holding ENIs in the subnets, and the subnets won't delete while ENIs exist, and the VPC won't delete while subnets exist. Removing the Service first lets AWS reap the NLB cleanly **before** Terraform starts dismantling the network.

### What does NOT get destroyed

| Resource | Why preserved |
|---|---|
| ECR repositories `rental/api`, `rental/client` | Not managed by this Terraform — created out of band |
| ECR images | Same reason |
| Secrets Manager entries | Soft-deleted with 7-day recovery — restored automatically on next deploy |
| S3 state bucket + DynamoDB lock table | Created bootstrap (would orphan Terraform if destroyed) |

---

## 6. The Secrets Lifecycle (Soft-Delete + Auto-Restore)

This is the trickiest part of the pipeline and worth its own diagram.

```
        ┌──────────────────────────────────────────────────────────┐
        │  Day 0  — destroy.yml runs                               │
        │  → AWS Secrets Manager marks /rentalapp/eks-prod/*       │
        │    for deletion in 7 days (recovery_window_in_days=7)    │
        │  → Secrets vanish from list-secrets output, but exist    │
        └─────────────────────┬────────────────────────────────────┘
                              │
                              │  Day 0..7
                              ▼
        ┌──────────────────────────────────────────────────────────┐
        │  User pushes to main → deploy.yml runs                   │
        │                                                          │
        │  Step "Restore scheduled-for-deletion secrets":          │
        │   for each (mongodb_uri, session_secret, jwt_secret):    │
        │     describe-secret → check .DeletedDate                 │
        │     if scheduled-for-deletion:                           │
        │        aws secretsmanager restore-secret                 │
        │        terraform import module.app_secrets.aws_...       │
        │                                                          │
        │  Now state has them, Terraform sees them as              │
        │  already-managed.                                        │
        └─────────────────────┬────────────────────────────────────┘
                              │
                              ▼
        ┌──────────────────────────────────────────────────────────┐
        │  Terraform plan / apply                                  │
        │  → secret resources: no change (or version updated)      │
        │  → values preserved unchanged across destroy/recreate    │
        └──────────────────────────────────────────────────────────┘
```

**If user waits >7 days**, the secrets are gone, and `terraform apply` creates them fresh from the `TF_VAR_*` values supplied via GitHub repo secrets — also fine. The 7-day window is the **convenience** path; the GitHub-secret path is the **disaster recovery** path.

---

## 7. Wiring Between Workflows

The three workflows don't directly invoke each other — but they're tightly coupled through **shared state**:

```
       ┌──────────────────┐         ┌──────────────────┐
       │  pr-validation   │         │     destroy      │
       └────────┬─────────┘         └────────┬─────────┘
                │                            │
                │ reads S3 state             │ writes S3 state
                │ (plan only)                │ (destroy resources)
                ▼                            ▼
       ┌──────────────────────────────────────────────┐
       │  S3 bucket: terraform state                  │
       │  DynamoDB: state lock                        │
       └────────────────────┬─────────────────────────┘
                            ▲
                            │ reads + writes S3 state
                            │ (plan + apply)
                            │
                   ┌────────┴─────────┐
                   │      deploy      │
                   └──────────────────┘
```

DynamoDB locking ensures only **one** workflow can run `apply`/`destroy` at a time. If deploy is running and you trigger destroy, destroy will wait until deploy finishes (or fail with lock acquire timeout).

---

## 8. Failure Modes & Behaviors

| Workflow | Failure | Behavior |
|---|---|---|
| deploy | Build fails | Job stops, infra untouched |
| deploy | Plan fails | Job stops, infra untouched |
| deploy | Apply fails partway | Some resources created; Terraform state captures partial state; re-running picks up where it left off |
| deploy | Rollout status fails (after apply succeeded) | Job marked failed even though infra is updated; check `kubectl describe pod` |
| pr-validation | Anything | Posts comment with red ❌, PR check goes red, but never touches prod |
| destroy | Wrong confirmation string | Fails at step 1, nothing destroyed |
| destroy | K8s pre-cleanup fails | Continues to terraform destroy (best-effort step); destroy may stall on VPC dependencies — manually delete the stuck ENIs/LB in console if so |
| destroy | Terraform destroy fails | Some resources gone, some remain; rerun usually works |

---

## 9. Concurrency & Safety

| Mechanism | Effect |
|---|---|
| DynamoDB state lock | Only one terraform op runs at a time across all workflows + local |
| `permissions: id-token: write, contents: read` minimum | Workflows can't push commits or modify other repos |
| OIDC trust policy `sub` restriction | Only this specific repo + branch can assume the AWS role |
| Destroy confirmation gate | No accidental clicks |
| PR validation runs before merge | Plan diffs visible to reviewer |
| Image digest pinning | Pods can't be silently swapped via tag mutation |
| `secrets.MONGODB_URI` / `SESSION_SECRET` / `JWT_SECRET` | Stored encrypted in GitHub, never written to logs |

---

## 10. Operational Cheat Sheet

### Deploy a new app version
```
git push origin main          # or merge a PR
# watch Actions → Deploy EKS
```

### Plan an infra change safely
```
git checkout -b feat/something
# edit terraform/
git push origin feat/something
# open PR; read the auto-posted plan comment; iterate
# when happy, merge → deploy.yml applies it
```

### Destroy the environment
```
# In GitHub UI:
#   Actions → Destroy EKS → Run workflow
#   confirm: DESTROY
#   skip_k8s: false
```

### Recreate after destroy
```
# Push anything to main (or click "Re-run" on a previous deploy run)
# Within 7 days: secrets auto-restored.
# After 7 days: secrets recreated from GitHub secrets.
```

### Find the live URL
```bash
cd terraform/environments/eks-production
terraform output app_url
# or
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{"http://"}{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

### Tail logs
```bash
kubectl logs -n rental -l app=api --tail=50 -f
kubectl logs -n rental -l app=client --tail=50 -f
```

---

## 11. What's NOT Automated (Yet)

These are reasonable next iterations:
- **Tests stage** — run `npm test` for api/client before the build step. Currently no test gate.
- **Slack notification** on deploy success/failure.
- **Auto-rollback** if `kubectl rollout status` fails (today it just leaves the failed ReplicaSet).
- **Preview environments per PR** — would require separate Terraform workspaces.
- **Promotion across envs** (dev → staging → prod) — today there's only one env.
- **Drift detection** — a scheduled `terraform plan` that alerts if the live infra drifts from code.

---

## 12. Required GitHub Configuration

For these workflows to run end-to-end, the repo needs:

**Repo secrets** (Settings → Secrets and variables → Actions):

| Name | Value |
|---|---|
| `AWS_ROLE_ARN` | `arn:aws:iam::664418980347:role/rentalapp-gha-deploy` |
| `MONGODB_URI` | full Atlas connection string |
| `SESSION_SECRET` | random 64-char string |
| `JWT_SECRET` | random 64-char string |

**Workflow permissions** (Settings → Actions → General → Workflow permissions):
- Set "Read and write permissions" if you want pr-validation to post comments. (Alternatively, the workflow already declares `pull-requests: write` which works on most repos.)

**Branch protection** (recommended for prod):
- Require `pr-validation` to pass before merge.
- Require at least 1 approving review.
- Restrict who can run `Destroy EKS` (via environment protection rules).
