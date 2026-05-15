# CloudWatch Observability Setup (Minimal)

EKS audit logs are already enabled and flowing to CloudWatch. Use these tools to monitor your cluster.

## Quick Start

### 1. View Audit Logs (Last 1 Hour)
```bash
./scripts/view-audit-logs.sh 1
```

**Output includes:**
- Recent audit events
- Authentication failures
- Sensitive resource access (secrets, roles, bindings)
- Failed API calls

### 2. View Audit Logs (Last 24 Hours)
```bash
./scripts/view-audit-logs.sh 24
```

### 3. Create CloudWatch Dashboard
```bash
./scripts/setup-cloudwatch-dashboard.sh
```

**Dashboard widgets:**
- EKS node count
- API request rate & errors
- Failed API operations
- Sensitive resource access
- Authentication failures

### 4. Set Up Alarms (Optional)

First, create an SNS topic for alerts:
```bash
aws sns create-topic --name eks-alerts --region us-east-1
# Returns: TopicArn=arn:aws:sns:us-east-1:123456789012:eks-alerts

# Subscribe your email
aws sns subscribe --topic-arn arn:aws:sns:us-east-1:123456789012:eks-alerts \
  --protocol email --notification-endpoint your@email.com
```

Then set up alarms:
```bash
./scripts/setup-cloudwatch-alarms.sh arn:aws:sns:us-east-1:123456789012:eks-alerts
```

---

## Manual CloudWatch Logs Queries

### View Recent Events
```bash
aws logs tail /aws/eks/rentalapp-eks-prod-eks/cluster --follow
```

### Query Authentication Failures (Last 24h)
```bash
aws logs start-query \
  --log-group-name /aws/eks/rentalapp-eks-prod-eks/cluster \
  --start-time $(date -d '24 hours ago' +%s) \
  --end-time $(date +%s) \
  --query-string '
    fields @timestamp, user.username, verb
    | filter responseStatus.code = 401
    | stats count() as auth_failures'
```

### Query API Errors (Last 1h)
```bash
aws logs start-query \
  --log-group-name /aws/eks/rentalapp-eks-prod-eks/cluster \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string '
    fields @timestamp, verb, responseStatus.code, objectRef.name
    | filter responseStatus.code >= 400
    | stats count() by verb, responseStatus.code'
```

### Query Sensitive Resource Access (Last 1h)
```bash
aws logs start-query \
  --log-group-name /aws/eks/rentalapp-eks-prod-eks/cluster \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string '
    fields @timestamp, user.username, verb, objectRef.resource, objectRef.name
    | filter objectRef.resource in ["secrets", "roles", "rolebindings"]
    | filter verb != "watch"
    | stats count() by user.username, verb, objectRef.resource'
```

---

## CloudWatch Logs Insights Console

For interactive querying:
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:logs-insights$3FqueryDetail$3F~()
```

Log group: `/aws/eks/rentalapp-eks-prod-eks/cluster`

**Pre-built queries:**

1. **Authentication errors**
```
fields @timestamp, user.username, verb, responseStatus.code
| filter responseStatus.code = 401
| stats count() by user.username
```

2. **API latency (slow operations)**
```
fields @timestamp, verb, responseStatus.code, requestObject.apiVersion, elapsedTime
| filter elapsedTime > 1000
| sort elapsedTime desc
| limit 20
```

3. **Pod creation events**
```
fields @timestamp, verb, objectRef.kind, objectRef.name, user.username
| filter verb = "create" and objectRef.kind = "Pod"
```

4. **RBAC changes**
```
fields @timestamp, verb, objectRef.resource, objectRef.name, user.username
| filter objectRef.resource in ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
| filter verb in ["create", "update", "patch", "delete"]
```

---

## What's Logged

**Enabled audit levels:**
- `api` - API server requests/responses
- `audit` - Important operations (RBAC, deployments)
- `authenticator` - Auth events
- `controllerManager` - Controller manager operations
- `scheduler` - Scheduler decisions

**Retention:** 1 week (AWS default)

To increase retention:
```bash
aws logs put-retention-policy \
  --log-group-name /aws/eks/rentalapp-eks-prod-eks/cluster \
  --retention-in-days 30
```

---

## Next Steps

1. **Today:** Test `./scripts/view-audit-logs.sh 1`
2. **Week 1:** Set up dashboard with `./scripts/setup-cloudwatch-dashboard.sh`
3. **Week 2:** Subscribe to SNS alerts and set up alarms
4. **Week 3:** Integrate with Slack/PagerDuty if needed

---

## Troubleshooting

**"Log group not found"**
```bash
aws logs describe-log-groups --query 'logGroups[?contains(logGroupName, `eks`)].{Name:logGroupName, CreationTime:creationTime}'
```

**"No events returned"**
- Cluster may be new and not have many events yet
- Check that audit logging is enabled: `aws eks describe-cluster --name rentalapp-eks-prod-eks --query 'cluster.logging.clusterLogging'`

**"Permission denied"**
- Ensure your AWS IAM user has `logs:FilterLogEvents` and `logs:DescribeLogGroups` permissions

---

**Status:** ✅ CloudWatch audit logs enabled and observable  
**Setup time:** ~5 minutes  
**Cost:** Included in EKS, ~$0.50/GB for logs stored
