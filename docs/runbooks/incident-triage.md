# Incident Triage Runbook

## Overview

This runbook covers initial triage steps when a CloudWatch alarm fires or an operational issue is reported for the UN17 Village Rooftop Gardens platform.

## Alarm Reference

| Alarm | Metric | Threshold | Likely cause |
|-------|--------|-----------|--------------|
| `*-lambda-errors` | Lambda Errors | >0 for 2×5 min | Application bug, dependency failure |
| `*-lambda-throttles` | Lambda Throttles | >0 | Concurrency limit reached |
| `*-ses-bounces` | SES Bounce | >5/hr | Invalid recipient addresses |
| `*-ses-complaints` | SES Complaint | >1/hr | Spam reports, consent issue |

## Triage Steps

### 1. Acknowledge the alert

- Check the SNS notification email for alarm name and environment.
- Open the [CloudWatch dashboard](https://eu-north-1.console.aws.amazon.com/cloudwatch/home?region=eu-north-1#dashboards) for the affected environment.

### 2. Assess severity

- **P1 (Critical):** API fully down, DB unreachable. Escalate immediately.
- **P2 (High):** Elevated error rate, throttles blocking users.
- **P3 (Medium):** Resource nearing limits (CPU, memory, connections).
- **P4 (Low):** SES bounces/complaints, non-blocking.

### 3. Investigate Lambda errors

1. Open CloudWatch Logs for the API Lambda:
   ```
   Log group: /<naming-prefix>/api
   ```
2. Filter for error-level log entries (JSON logs):
   ```
   { $.level = "error" }
   ```
3. Check for recent deployments that may have introduced the issue:
   ```bash
   gh run list --workflow=deploy.yml --limit 5
   ```
4. If related to a recent deploy, consider rolling back:
   ```bash
   aws lambda update-function-code \
     --function-name <function-name> \
     --s3-bucket <deploy-bucket> \
     --s3-key <previous-version-key>
   ```

### 4. Investigate Lambda throttles

1. Check current reserved concurrency setting in Terraform variables.
2. Review concurrent executions metric on the dashboard.
3. If `lambda_reserved_concurrency` is set to `-1` (unrestricted), throttles indicate an **account-level** concurrent execution limit has been reached, not a function-level issue. Check the AWS Lambda service quota.
4. If traffic is legitimate, increase `lambda_reserved_concurrency` via Terraform or request an account-level limit increase.

### 5. Investigate database (shared RDS) issues

Greenspace runs on the **shared RDS instance owned by
`ammonl/un17-infra-shared`**; the dedicated per-environment RDS instances
and their CloudWatch alarms/dashboard widgets were removed in #347. Database
metrics, alarms, and Performance Insights for the shared instance live in that
repo's monitoring, so coordinate with the shared-db owner for instance-level
investigation.

From the Greenspace side:

1. Check the API Lambda logs (`/<naming-prefix>/api`) for database connection
   errors or timeouts — these surface as elevated `*-lambda-errors`.
2. For suspected long-running or blocked queries, escalate to the shared-db
   owner to inspect Performance Insights and top SQL statements on the shared
   instance.
3. For connection exhaustion, check if Lambda is scaling faster than the shared
   instance's connection pool can handle, and review `lambda_reserved_concurrency`.

### 6. Investigate SES issues

1. Check the SES console for bounce/complaint details.
2. Review the `emails` database table for recent `failed` status entries:
   ```sql
   SELECT * FROM emails WHERE status = 'failed' ORDER BY created_at DESC LIMIT 20;
   ```
3. For high bounce rates, verify recipient email addresses in registrations.
4. For complaints, review email content and sending consent.

### 7. Resolve and document

1. Apply the fix (code change, config update, or infrastructure adjustment).
2. Verify the alarm returns to OK state.
3. Document the incident in a GitHub issue with:
   - Timeline of events
   - Root cause
   - Resolution
   - Follow-up actions (if any)

## Escalation

- **Primary contact:** Ammon Larson (ammonl@hotmail.com)
- **Infrastructure:** Check repository `CODEOWNERS` or PR history for recent contributors.
