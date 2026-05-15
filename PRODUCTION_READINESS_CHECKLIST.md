# EKS Production Readiness Checklist

**Status:** Partially hardened, HTTP-only, ready for pre-production validation.

This checklist outlines all remaining security, operational, and observability improvements required before moving RentalApp EKS to full production traffic.

---

## Phase 1: Security Hardening (Immediate)

### 1.1 API Server Endpoint Access Control
- [x] **Terraform Check:** Cluster endpoint CIDR is restricted (not `0.0.0.0/0`)
  - Current: `["59.103.217.174/32"]` (admin IP)
  - **Action:** Before production cutover, narrow to your office/VPN CIDR or bastion host only
  - **File:** [terraform/environments/eks-production/terraform.tfvars](terraform/environments/eks-production/terraform.tfvars#L4)
  - **Risk if skipped:** Anyone on the internet can discover and enumerate your cluster API

- [ ] **Verify:** Apply terraform and confirm EKS endpoint only accepts traffic from the restricted CIDR
  ```bash
  cd terraform/environments/eks-production
  terraform apply -var-file=terraform.tfvars
  aws eks describe-cluster --name rentalapp-eks-prod-eks --region us-east-1 \
    --query 'cluster.resourcesVpcConfig.publicAccessCidrs' --output text
  ```

### 1.2 Node Group Security
- [ ] **IAM Node Role:** Verify the node role has minimal permissions
  - **File:** [terraform/modules/eks-cluster/main.tf](terraform/modules/eks-cluster/main.tf#L40-L60)
  - **Current policies:** `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`
  - **Action:** Do NOT attach additional policies like `AdministratorAccess` or `AmazonEC2FullAccess`
  - **Risk if skipped:** If a pod is compromised, attacker gains broad EC2/IAM permissions

- [ ] **IMDSv2:** Verify nodes are running IMDSv2 (metadata token-based, not open)
  ```bash
  aws ec2 describe-instances --query \
    'Reservations[0].Instances[0].MetadataOptions' --region us-east-1
  # Should see: HttpTokens=required, HttpPutResponseHopLimit=1
  ```
  - **If not set:** Edit the launch template or recreate the node group with metadata token requirement

### 1.3 RBAC & Service Accounts
- [x] **Service Account Tokens:** Auto-mounted tokens are disabled
  - Current: `automountServiceAccountToken: false` in both `rental-api` and `rental-client`
  - **File:** [k8s/base/rbac.yaml](k8s/base/rbac.yaml#L1-L15)

- [x] **Minimal Role:** API service account has only read permission on config
  - Current: `Role: rental-api-config-reader` (get on configmaps)
  - **File:** [k8s/base/rbac.yaml](k8s/base/rbac.yaml#L16-L40)

- [ ] **Review:** Ensure no cluster-admin or overly broad ClusterRoles are bound
  ```bash
  kubectl get clusterrolebindings -A | grep -i admin
  # Should show only system:* and possibly kube-system entries, NOT user namespaces
  ```

- [ ] **IRSA Setup (Optional but Recommended):** If pods need AWS API access in future
  - Example: S3, SQS, CloudWatch PutMetricData
  - **File:** OIDC provider is created: [terraform/modules/eks-cluster/main.tf](terraform/modules/eks-cluster/main.tf#L150-L157)
  - **Action:** Create IAM role with trust policy pointing to OIDC issuer + service account, then annotate pod SA
  - **Until then:** App stays stateless; external services (MongoDB) accessed via hardcoded secrets

### 1.4 Network Policies
- [x] **Default Deny:** All pods default-deny ingress and egress
  - **File:** [k8s/base/network-policies.yaml](k8s/base/network-policies.yaml#L1-L10)

- [x] **Explicit Allow Rules:** 7 policies enforce strict flows
  - API ← ingress-nginx (port 4000)
  - Client ← ingress-nginx (port 8080)
  - API → MongoDB Atlas (external egress)
  - API → DNS (egress to CoreDNS)
  - Client → DNS (egress to CoreDNS)
  - **File:** [k8s/base/network-policies.yaml](k8s/base/network-policies.yaml#L1-L220)

- [ ] **Verify Enforcement:** Confirm CNI plugin enforces policies
  ```bash
  kubectl get networkpolicies -n rental
  # Should list 7 policies
  kubectl get pods -n rental -l app=api -o jsonpath='{.items[0].metadata.name}' | \
    xargs -I{} kubectl exec -n rental {} -- timeout 5 curl http://unreachable.invalid || echo "Expected timeout (policy enforced)"
  ```

### 1.5 Pod Security Admission
- [x] **Restricted Profile:** Namespace enforces `pod-security.kubernetes.io/enforce: restricted`
  - Current: Enforces, warns, and audits at `restricted` level
  - **File:** [k8s/base/namespace.yaml](k8s/base/namespace.yaml#L1-L10)

- [x] **Container Security Context:** Both deployments run non-root, read-only FS, dropped capabilities
  - Current: `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `capabilities: drop: [ALL]`
  - **File:** [k8s/base/api-deployment.yaml](k8s/base/api-deployment.yaml#L60-L70) and [k8s/base/client-deployment.yaml](k8s/base/client-deployment.yaml#L60-L70)

- [ ] **Verify:** Test that a pod cannot execute privileged operations
  ```bash
  POD=$(kubectl get pods -n rental -l app=api -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n rental $POD -- whoami
  # Should show: node (non-root user)
  kubectl exec -n rental $POD -- touch /etc/test 2>&1 || echo "Expected read-only FS"
  ```

### 1.6 Secrets Management
- [x] **Encryption at Rest:** Kubernetes secrets stored in etcd (encrypted by default in EKS)
  - **File:** [k8s/overlays/eks-production/kustomization.yaml](k8s/overlays/eks-production/kustomization.yaml#L16-L19)

- [ ] **Rotation:** Implement automated secret rotation
  - **Option A (Recommended):** Install External Secrets Operator (ESO) to sync Secrets Manager ↔ k8s automatically
    ```bash
    helm repo add external-secrets https://charts.external-secrets.io
    helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace
    ```
  - **Option B:** Use k8s/run-eks.sh manually (current approach; acceptable for small teams)
  - **Until then:** Update secrets via AWS Secrets Manager CLI, then re-run `k8s/run-eks.sh` to sync

- [ ] **Audit Secret Access:** Enable Kubernetes audit logging to track secret reads
  ```bash
  # Cluster API logs are enabled; check CloudWatch
  aws logs describe-log-groups --query \
    'logGroups[?logGroupName==`/aws/eks/rentalapp-eks-prod-eks/cluster`]'
  ```

---

## Phase 2: Observability & Monitoring (Weeks 1–2)

### 2.1 Centralized Logging
- [ ] **CloudWatch Logs:** View API pod logs (STDOUT/STDERR captured by container runtime)
  ```bash
  # Logs should auto-appear in CloudWatch under /aws/eks/rentalapp-eks-prod-eks/
  aws logs tail /aws/eks/rentalapp-eks-prod-eks/ --follow
  ```

- [ ] **Application Logs:** Ensure API logs include request trace IDs and timestamps
  - **Action:** Add structured logging (JSON format) to the API app
  - Example Passport/Express middleware to log all auth events and API calls

- [ ] **ELK Stack (Optional but Recommended for Production):**
  - **Cost:** ~$50–100/month for managed Elasticsearch
  - **Alternative:** CloudWatch Container Insights (cheaper, simpler)
  - **Action if using ELK:**
    ```bash
    # Deploy via Helm
    helm repo add elastic https://helm.elastic.co
    helm install elasticsearch elastic/elasticsearch -n logging --create-namespace
    helm install kibana elastic/kibana -n logging
    # Configure Fluent Bit to forward logs: /rentals → Elasticsearch
    ```

### 2.2 Metrics & Alerting
- [x] **HPA Metrics:** metrics-server installed and collecting pod CPU/memory
  - **File:** [k8s/base/api-hpa.yaml](k8s/base/api-hpa.yaml) (API scales 2–4 replicas on 70% CPU)

- [ ] **Prometheus + Grafana (Recommended):**
  ```bash
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    -n monitoring --create-namespace --set grafana.adminPassword=<secure-password>
  # Access: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
  ```

- [ ] **CloudWatch Alarms:**
  - CPU > 85% on any pod
  - Memory > 90% on any pod
  - API error rate > 5% over 5 min
  - MongoDB connection timeouts
  ```bash
  aws cloudwatch put-metric-alarm --alarm-name api-cpu-high \
    --comparison-operator GreaterThanThreshold --evaluation-periods 2 \
    --metric-name CPUUtilization --namespace AWS/EKS --period 300 \
    --statistic Average --threshold 85 --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:alerts
  ```

### 2.3 Audit & Compliance
- [x] **EKS Cluster Audit Logs:** Enabled in Terraform
  - **File:** [terraform/modules/eks-cluster/main.tf](terraform/modules/eks-cluster/main.tf#L68-L72)
  - Logs: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`

- [ ] **Review Audit Logs:** Confirm critical events are logged
  ```bash
  aws logs describe-log-streams --log-group-name /aws/eks/rentalapp-eks-prod-eks/cluster
  ```

- [ ] **Backup Audit Trail:** Archive audit logs to S3 for compliance
  ```bash
  aws s3api put-bucket-versioning --bucket rental-audit-logs --versioning-configuration Status=Enabled
  # Configure CloudWatch → S3 export
  ```

---

## Phase 3: Networking & Traffic Management (Weeks 2–4)

### 3.1 DNS & Custom Domain (HTTPS)
- [ ] **Current Status:** HTTP-only on ELB hostname (`ae3b0296de3e84446aba612ab8ecb1ea-817453542.us-east-1.elb.amazonaws.com`)

- [ ] **For Production HTTPS:**
  1. Acquire a custom domain (e.g., `api.rentalapp.com`)
  2. Create Route53 A record pointing to ELB hostname
  3. Update ConfigMap `CLIENT_URL` to `https://api.rentalapp.com`
  4. Re-enable TLS in ingress:
     ```yaml
     # k8s/base/ingress.yaml
     spec:
       tls:
         - hosts:
             - api.rentalapp.com
           secretName: rental-tls
       rules:
         - host: api.rentalapp.com
           http: ...
     ```
  5. Set `SESSION_COOKIE_SECURE=true` in ConfigMap
  6. cert-manager will auto-issue Let's Encrypt cert

- [ ] **Test HTTPS:** Once deployed
  ```bash
  curl https://api.rentalapp.com/healthz
  # Should return {"status":"ok"}
  ```

### 3.2 Ingress Controller HA
- [x] **NGINX Replicas:** 2 replicas deployed
  - **File:** [k8s/run-eks.sh](k8s/run-eks.sh#L70)

- [ ] **Verify:** Check ingress controller pod distribution across nodes
  ```bash
  kubectl get pods -n ingress-nginx -o wide
  # Should see pods on different nodes if using PodAntiAffinity
  ```

### 3.3 Rate Limiting & DDoS Protection
- [x] **NGINX Rate Limit:** 20 req/sec per IP, 20 concurrent connections
  - **File:** [k8s/base/ingress.yaml](k8s/base/ingress.yaml#L7-L8)

- [ ] **AWS Shield (Optional):** Standard is free; Shield Advanced ($3k/month) offers DDoS mitigation
  - For this app, Shield Standard is likely sufficient initially

- [ ] **WAF (Optional):** AWS WAF can block common attacks (SQLi, XSS)
  - Attach to the NLB ingress controller for production

---

## Phase 4: Operational Readiness (Weeks 3–4)

### 4.1 Backup & Disaster Recovery
- [ ] **Persistent Data:** Only MongoDB (external service, managed by Atlas)
  - **Action:** Enable Atlas automated backups and point-in-time recovery
  - **Risk:** If Mongo connection is lost, app returns 503

- [ ] **Configuration Backup:** Store Kustomize manifests + Terraform in Git (already done)
  - **Action:** Add GitOps workflow (ArgoCD) to auto-deploy on Git push
  ```bash
  helm repo add argo https://argoproj.github.io/argo-helm
  helm install argocd argo/argo-cd -n argocd --create-namespace
  ```

- [ ] **Disaster Recovery Runbook:** Document RTO/RPO
  - **RTO:** ~5 min (reapply k8s manifests, scale up)
  - **RPO:** ~1 sec (MongoDB Atlas replication)

### 4.2 Cost Optimization
- [ ] **Current Estimate:**
  - EKS control plane: ~$73/month
  - 2 × t3.small nodes: ~$30/month
  - NLB: ~$32/month
  - Data transfer: ~$10/month
  - **Total:** ~$145/month

- [ ] **Optimization Options:**
  - Use Spot instances for non-critical workloads: save ~70% on compute
  - Set resource requests/limits accurately to avoid over-provisioning
  - Monitor CloudWatch metrics and right-size node count
  ```bash
  kubectl top nodes
  kubectl top pods -n rental
  ```

### 4.3 Runbooks & Escalation
- [ ] **On-call Runbook:**
  - Pod CrashLoopBackOff → check `kubectl logs`
  - API 5xx errors → check MongoDB connectivity
  - Ingress not responding → check NGINX pod logs
  - Helm chart update failures → rollback with `helm rollback`

- [ ] **Escalation Matrix:**
  - Tier 1 (App logs): Use CloudWatch or ELK
  - Tier 2 (Infrastructure): Check EC2 node health, EKS add-on status
  - Tier 3 (AWS Account): Check CloudTrail, service quotas, billing

---

## Phase 5: Pre-Production Validation (Final Week)

### 5.1 Load Testing
- [ ] **Tool:** Apache JMeter, k6, or Locust
- [ ] **Test Scenarios:**
  - 100 concurrent users accessing `/` (React SPA)
  - Login flow: 10 req/sec (POST `/api/auth/login`)
  - Protected API: 50 concurrent GET `/api/bikes`
  - Expected: All requests < 500ms, no 5xx errors

```bash
# Example with Apache Bench
ab -n 1000 -c 50 http://ae3b0296de3e84446aba612ab8ecb1ea-817453542.us-east-1.elb.amazonaws.com/
```

### 5.2 Failover Testing
- [ ] **Node Failure:** Kill one node, verify pod rescheduling
  ```bash
  # Cordon and drain the node
  kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
  # Verify pods moved to other nodes
  kubectl get pods -n rental -o wide
  ```

- [ ] **Pod Restart:** Kill a running pod, verify graceful restart
  ```bash
  POD=$(kubectl get pods -n rental -l app=api -o jsonpath='{.items[0].metadata.name}')
  kubectl delete pod $POD -n rental
  # Should see new pod spawn immediately
  ```

### 5.3 Security Scanning
- [ ] **Container Image Scan:** ECR can scan for vulnerabilities
  ```bash
  aws ecr describe-image-scan-findings --repository-name rental/api \
    --image-id imageTag=latest --region us-east-1
  ```

- [ ] **RBAC Audit:** Ensure no overly permissive roles
  ```bash
  kubectl get clusterrole -A
  # Should NOT see anything with "*" in rules
  ```

### 5.4 User Acceptance Testing (UAT)
- [ ] **Browser Testing:**
  - Login flow works (session cookies set correctly)
  - Protected pages return 200 (not 401)
  - Bike list loads and renders
  - Create/update/delete reservations work

- [ ] **Mobile Testing:** React app responsive on mobile browsers

---

## Phase 6: Production Cutover (Go-Live)

### 6.1 Pre-Cutover Checklist
- [ ] All previous phases complete
- [ ] Both ECS and EKS running in parallel for 48+ hours with no errors
- [ ] Runbooks signed off by ops team
- [ ] On-call rotation scheduled
- [ ] Rollback plan reviewed

### 6.2 Cutover Steps
1. **Announce maintenance window** (if needed): 5–10 min expected downtime
2. **DNS switch:** Point `rental.example.com` (or custom domain) from ALB → NLB (EKS)
   ```bash
   aws route53 change-resource-record-sets --hosted-zone-id Z123... \
     --change-batch file://switch-to-eks.json
   # Old: weighted routing to ALB (weight 100)
   # New: weighted routing to NLB (weight 100)
   ```
3. **Verify traffic:** Monitor CloudWatch logs, confirm no 5xx errors
4. **Scale down ECS:** Set ECS service desired count to 0 (keep running for 24 hrs as backup)
5. **Monitor for 24 hours:** Alert on any anomalies
6. **Final sign-off:** Decommission ECS if 24 hrs passes with no issues

### 6.3 Post-Cutover
- [ ] Document any issues or surprises in a retrospective
- [ ] Update runbooks based on lessons learned
- [ ] Plan cost monitoring and optimization
- [ ] Schedule post-mortems for any incidents

---

## Summary Matrix

| Category | Status | Owner | ETA |
|----------|--------|-------|-----|
| **Security** | 70% | DevOps | Week 1 |
| **Observability** | 40% | SRE | Week 2 |
| **Networking** | 50% | DevOps | Week 3 |
| **Operations** | 30% | Ops | Week 4 |
| **Testing** | 0% | QA | Week 5 |
| **Cutover** | 0% | All | Week 6 |

---

## Quick Command Reference

### Immediate Actions (Today)
```bash
# 1. Verify cluster endpoint CIDR
aws eks describe-cluster --name rentalapp-eks-prod-eks --region us-east-1 \
  --query 'cluster.resourcesVpcConfig.publicAccessCidrs'

# 2. Check pod security context
kubectl get pods -n rental -o jsonpath='{.items[0].spec.containers[0].securityContext}' | jq

# 3. Verify network policies
kubectl get networkpolicies -n rental

# 4. View recent logs
kubectl logs -n rental -l app=api --tail=50 --timestamps=true
```

### Week 1 Actions
```bash
# Enable monitoring
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

# Test failover
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --dry-run=client
```

### Week 2 Actions
```bash
# Deploy External Secrets Operator (for automated secret sync)
helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace

# Create AWS Secrets Manager → k8s SyncSecretStore
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets
  namespace: rental
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: rental-api
EOF
```

---

**Document Revision:** May 3, 2026 | **Next Review:** After Phase 1 completion
