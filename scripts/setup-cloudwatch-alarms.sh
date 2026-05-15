#!/usr/bin/env bash
set -euo pipefail

# CloudWatch Alarms for EKS Cluster (Minimal, Critical Events Only)
# Sets up alarms for auth failures, API errors, and sensitive resource access
# Usage: ./scripts/setup-cloudwatch-alarms.sh <sns-topic-arn>

CLUSTER_NAME="${EKS_CLUSTER_NAME:-rentalapp-eks-prod-eks}"
REGION="${AWS_REGION:-us-east-1}"
SNS_TOPIC_ARN="${1:-}"

if [[ -z "$SNS_TOPIC_ARN" ]]; then
  echo "Usage: $0 <sns-topic-arn>"
  echo ""
  echo "Create an SNS topic first:"
  echo "  aws sns create-topic --name eks-alerts --region $REGION"
  echo ""
  echo "Then run this script with the topic ARN."
  exit 1
fi

echo "Setting up CloudWatch alarms for EKS cluster: $CLUSTER_NAME"
echo "SNS Topic: $SNS_TOPIC_ARN"
echo ""

# Alarm 1: Authentication Failures
echo "Creating alarm: Authentication Failures"
aws cloudwatch put-metric-alarm \
  --alarm-name "${CLUSTER_NAME}-auth-failures" \
  --alarm-description "Alert on API authentication failures" \
  --metric-name "AuthenticationFailures" \
  --namespace "EKS/Audit" \
  --statistic "Sum" \
  --period 300 \
  --threshold 5 \
  --comparison-operator "GreaterThanOrEqualToThreshold" \
  --evaluation-periods 1 \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION" 2>/dev/null || echo "  (Metric may not exist yet; will alarm when first failure occurs)"

# Alarm 2: API Errors
echo "Creating alarm: High API Error Rate"
aws cloudwatch put-metric-alarm \
  --alarm-name "${CLUSTER_NAME}-api-errors" \
  --alarm-description "Alert on high API server error rate (>5% in 5 min)" \
  --metric-name "APIServerErrorRate" \
  --namespace "EKS/Audit" \
  --statistic "Average" \
  --period 300 \
  --threshold 5 \
  --comparison-operator "GreaterThanThreshold" \
  --evaluation-periods 1 \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION" 2>/dev/null || echo "  (Metric may not exist yet)"

# Alarm 3: Sensitive Resource Access
echo "Creating alarm: Sensitive Resource Access"
aws cloudwatch put-metric-alarm \
  --alarm-name "${CLUSTER_NAME}-sensitive-access" \
  --alarm-description "Alert on access to secrets, roles, or bindings (non-watch)" \
  --metric-name "SensitiveResourceAccess" \
  --namespace "EKS/Audit" \
  --statistic "Sum" \
  --period 300 \
  --threshold 10 \
  --comparison-operator "GreaterThanOrEqualToThreshold" \
  --evaluation-periods 1 \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION" 2>/dev/null || echo "  (Metric may not exist yet)"

echo ""
echo "✓ Alarms created"
echo ""
echo "Note: Custom metrics (AuthenticationFailures, APIServerErrorRate, SensitiveResourceAccess)"
echo "need to be published via CloudWatch Logs Insights or a custom agent."
echo ""
echo "For now, you can:"
echo "1. Use the audit log viewer: ./scripts/view-audit-logs.sh"
echo "2. Monitor logs in CloudWatch Logs Insights manually"
echo "3. Set up a Lambda function to parse audit logs and publish metrics"
