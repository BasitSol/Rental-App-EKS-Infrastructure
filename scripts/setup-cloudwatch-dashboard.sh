#!/usr/bin/env bash
set -euo pipefail

# CloudWatch Dashboard for EKS Cluster Monitoring (Minimal)
# Creates a dashboard with critical metrics and audit log insights
# Usage: ./scripts/setup-cloudwatch-dashboard.sh

CLUSTER_NAME="${EKS_CLUSTER_NAME:-rentalapp-eks-prod-eks}"
REGION="${AWS_REGION:-us-east-1}"
DASHBOARD_NAME="${CLUSTER_NAME}-minimal-dashboard"

echo "Creating CloudWatch dashboard: $DASHBOARD_NAME"

# Dashboard definition with key metrics
DASHBOARD_BODY=$(cat <<'EOF'
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          [ "AWS/EKS", "cluster_node_count", { "stat": "Average" } ],
          [ ".", "cluster_node_count_max", { "stat": "Maximum" } ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "REGION_PLACEHOLDER",
        "title": "EKS Node Count"
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "fields @timestamp, @message\n| filter ispresent(responseStatus.code)\n| stats count() as total_requests, sum(if(responseStatus.code >= 400, 1, 0)) as errors by bin(5m)",
        "region": "REGION_PLACEHOLDER",
        "title": "API Server Request Rate & Errors",
        "queryId": "eks-request-rate"
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "fields @timestamp, user.username, verb, objectRef.resource, responseStatus.code\n| filter responseStatus.code >= 400\n| stats count() as failure_count by verb, responseStatus.code",
        "region": "REGION_PLACEHOLDER",
        "title": "Failed API Operations (Last 1h)",
        "queryId": "eks-failures"
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "fields @timestamp, user.username, verb, objectRef.resource, objectRef.name\n| filter objectRef.resource in [\"secrets\", \"roles\", \"rolebindings\", \"clusterroles\", \"clusterrolebindings\"]\n| stats count() as access_count by user.username, verb, objectRef.resource",
        "region": "REGION_PLACEHOLDER",
        "title": "Sensitive Resource Access",
        "queryId": "eks-sensitive"
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "fields @timestamp, user.username\n| filter user.username like /system:unauthenticated/ or responseStatus.code = 401\n| stats count() as auth_failures by @timestamp, user.username",
        "region": "REGION_PLACEHOLDER",
        "title": "Authentication Failures",
        "queryId": "eks-auth-fails"
      }
    }
  ]
}
EOF
)

# Replace region placeholder
DASHBOARD_BODY="${DASHBOARD_BODY//REGION_PLACEHOLDER/$REGION}"

# Create dashboard
aws cloudwatch put-dashboard \
  --dashboard-name "$DASHBOARD_NAME" \
  --dashboard-body "$DASHBOARD_BODY" \
  --region "$REGION"

echo "✓ Dashboard created: $DASHBOARD_NAME"
echo ""
echo "View dashboard:"
echo "  aws cloudwatch get-dashboard --dashboard-name $DASHBOARD_NAME --region $REGION"
echo ""
echo "Open in AWS Console:"
echo "  https://console.aws.amazon.com/cloudwatch/home?region=$REGION#dashboards:name=$DASHBOARD_NAME"
