#!/usr/bin/env bash
set -euo pipefail

# CloudWatch Audit Log Viewer for EKS
# Queries and displays critical events from EKS cluster audit logs
# Usage: ./scripts/view-audit-logs.sh [hours_back]

CLUSTER_NAME="${EKS_CLUSTER_NAME:-rentalapp-eks-prod-eks}"
REGION="${AWS_REGION:-us-east-1}"
LOG_GROUP="/aws/eks/${CLUSTER_NAME}/cluster"
HOURS_BACK="${1:-1}"

# Calculate timestamp for CloudWatch Logs query
START_TIME=$(date -d "$HOURS_BACK hours ago" +%s)000
END_TIME=$(date +%s)000

echo "=== EKS Cluster Audit Logs (Last $HOURS_BACK hour(s)) ==="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Log Group: $LOG_GROUP"
echo ""

# Query: All audit events (limit to last 100)
echo "--- Recent Audit Events (last 100) ---"
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --region "$REGION" \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --filter-pattern "" \
  --max-items 100 \
  --query 'events[*].[timestamp,message]' \
  --output text | \
  while read -r ts msg; do
    # Convert timestamp and pretty-print JSON
    if [[ -n "$ts" ]]; then
      date_str=$(date -d @$((ts / 1000)) '+%Y-%m-%d %H:%M:%S')
      echo "$date_str | $msg" | jq -R 'fromjson?' 2>/dev/null || echo "$date_str | $msg"
    fi
  done

# Query: Authentication failures
echo ""
echo "--- Authentication Failures ---"
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --region "$REGION" \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --filter-pattern '{ $.verb = "*" && $.stage = "ResponseComplete" && $.responseStatus.code >= 400 }' \
  --query 'events[*].message' \
  --output text | jq -R 'fromjson?' 2>/dev/null | jq -c '{user: .user.username, verb: .verb, object: .objectRef.name, code: .responseStatus.code}' || echo "No auth failures"

# Query: API calls to sensitive resources (secrets, rbac)
echo ""
echo "--- Sensitive Resource Access (secrets, roles, rolebindings) ---"
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --region "$REGION" \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --filter-pattern '{ ($.objectRef.resource = "secrets" || $.objectRef.resource = "roles" || $.objectRef.resource = "rolebindings") && $.verb != "watch" }' \
  --query 'events[*].message' \
  --output text | jq -R 'fromjson?' 2>/dev/null | jq -c '{user: .user.username, verb: .verb, resource: .objectRef.resource, name: .objectRef.name, namespace: .objectRef.namespace}' || echo "No sensitive access"

# Query: Failed API calls
echo ""
echo "--- Failed API Calls (non-2xx, non-3xx) ---"
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --region "$REGION" \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --filter-pattern '{ $.responseStatus.code >= 400 }' \
  --query 'events[*].message' \
  --output text | jq -R 'fromjson?' 2>/dev/null | jq -c '{user: .user.username, verb: .verb, status: .responseStatus.code, object: .objectRef.name}' | head -20 || echo "No errors"

echo ""
echo "=== End of Audit Log Summary ==="
