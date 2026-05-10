# Backup & Restore Runbook

## Overview

This runbook covers RDS automated backup management and point-in-time restore procedures for the UN17 Village Rooftop Gardens PostgreSQL database.

## Backup Configuration

| Setting | Staging | Production |
|---------|---------|------------|
| Backup retention | 7 days | 35 days |
| Backup window | 03:00–04:00 UTC | 03:00–04:00 UTC |
| Multi-AZ | No | No |
| Final snapshot on delete | No | Yes |
| Encryption | KMS (data key) | KMS (data key) |

Backups are configured via Terraform in `infra/terraform/modules/greenspace_stack/database.tf`.

## Listing Available Backups

```bash
aws rds describe-db-snapshots \
  --db-instance-identifier greenspace-<environment>-2026-postgres \
  --query "DBSnapshots[*].{ID:DBSnapshotIdentifier,Created:SnapshotCreateTime,Status:Status}" \
  --output table \
  --region eu-north-1
```

## Point-in-Time Restore

RDS supports restoring to any point within the backup retention window.

### 1. Identify the target restore time

Determine the exact UTC timestamp to restore to. This is typically just before the data loss or corruption event.

### 2. Restore to a new instance

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier greenspace-<environment>-2026-postgres \
  --target-db-instance-identifier greenspace-<environment>-2026-postgres-restored \
  --restore-time "2026-03-01T12:00:00Z" \
  --db-instance-class db.t4g.micro \
  --db-subnet-group-name greenspace-<environment>-2026-db \
  --vpc-security-group-ids <db-security-group-id> \
  --no-multi-az \
  --region eu-north-1
```

**Important:** Always restore to a **new** instance. Never restore in-place on the production instance.

**Note:** Both staging and prod run single-AZ on `db.t4g.micro`. Adjust `--db-instance-class` if the source environment has been resized.

### 3. Wait for the restored instance to become available

```bash
aws rds wait db-instance-available \
  --db-instance-identifier greenspace-<environment>-2026-postgres-restored \
  --region eu-north-1
```

### 4. Verify restored data

Connect to the restored instance and verify:

```bash
psql -h <restored-endpoint> -U greenspace -d greenspace -c "
  SELECT COUNT(*) FROM registrations;
  SELECT COUNT(*) FROM emails;
  SELECT MAX(created_at) FROM audit_events;
"
```

Compare row counts and latest timestamps against expected values.

### 5. Promote restored instance (if applicable)

If the restored data is correct and you need to replace the primary:

1. Update the application to point to the restored instance endpoint.
2. Update Terraform state to adopt the restored instance (or rename it).
3. Delete the original (corrupted) instance once the restored one is confirmed working.

**For production restores, always get explicit approval before proceeding.**

### 6. Clean up

If the restore was a drill or the restored instance is no longer needed:

```bash
aws rds delete-db-instance \
  --db-instance-identifier greenspace-<environment>-2026-postgres-restored \
  --skip-final-snapshot \
  --region eu-north-1
```

## Snapshot Restore

To restore from a specific snapshot instead of point-in-time:

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier greenspace-<environment>-2026-postgres-restored \
  --db-snapshot-identifier <snapshot-identifier> \
  --db-instance-class db.t4g.micro \
  --db-subnet-group-name greenspace-<environment>-2026-db \
  --vpc-security-group-ids <db-security-group-id> \
  --region eu-north-1
```

## Restore Drill Schedule

Run a restore drill quarterly to verify backup integrity:

1. Restore to a new instance (staging environment).
2. Verify data integrity (row counts, recent records).
3. Document results in a GitHub issue.
4. Delete the test instance.

## References

- [RDS Point-in-Time Recovery](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIT.html)
- Database Terraform config: `infra/terraform/modules/greenspace_stack/database.tf`
- Incident triage: `docs/runbooks/incident-triage.md`
- Shared-RDS migration runbook: `docs/runbooks/shared-rds-migration.md`
