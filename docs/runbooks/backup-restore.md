# Backup & Restore Runbook

## Overview

Greenspace's transactional data lives on the **shared RDS instance owned by
`ammonlarson/infra-shared-db`** (databases `greenspace_staging` and
`greenspace_prod`). The dedicated per-environment RDS instances were
decommissioned in #347 after the shared-db cutover (#342 / #346).

As a result, RDS automated backups, snapshots, and point-in-time restore for
the live database are **managed by the `ammonlarson/infra-shared-db` repo**, not
by this stack. Backup retention, the backup window, and encryption settings for
the shared instance are configured there. Refer to that repo's runbook for the
authoritative restore procedure.

For the data-migration context (how the Greenspace schema and data were moved
onto the shared instance), see `docs/runbooks/shared-rds-migration.md`.

## Restoring Greenspace data on the shared RDS

The shared RDS hosts one database per Greenspace environment. Restore work is
performed by the shared-db owner, but the Greenspace-specific steps are:

1. **Identify the target restore point** — the UTC timestamp just before the
   data-loss or corruption event.
2. **Coordinate with the shared-db owner** to restore the shared instance (or a
   clone of it) to that point in time. Never restore in place on the live shared
   instance; restore to a new instance and validate first.
3. **Verify restored Greenspace data** against the restored instance:

   ```bash
   psql -h <restored-endpoint> -U greenspace_<env> -d greenspace_<env> -c "
     SELECT COUNT(*) FROM registrations;
     SELECT COUNT(*) FROM emails;
     SELECT MAX(created_at) FROM audit_events;
   "
   ```

   Compare row counts and latest timestamps against expected values.
4. **Cut back over** by repointing the relevant `rds/shared/greenspace_<env>`
   Secrets Manager secret (consumed by the API Lambda via `DB_SECRET_ID`) at the
   validated host, or by promoting the restored instance. For production, always
   get explicit approval before proceeding.

## Decommissioning the dedicated RDS (one-time, #347)

The dedicated per-environment RDS stack is removed from Terraform in #347. The
teardown applies (destroys) carry two operational caveats:

- **Final snapshot (prod):** the prod instance's retained state keeps
  `skip_final_snapshot = false` and `final_snapshot_identifier =
  greenspace-prod-2026-final`, so `terraform destroy` takes a final snapshot
  **automatically** as it deletes `greenspace-prod-2026-postgres`. Taking an
  additional manual snapshot beforehand is optional belt-and-suspenders; the
  data was already migrated to and validated on the shared RDS (#340). Staging
  keeps `skip_final_snapshot = true`, so no snapshot is retained there (QA
  scratch space).
- **Deletion protection (prod):** the prod instance has `deletion_protection =
  true` in state. Because the resource is removed from config, Terraform cannot
  flip it off first — disable it out-of-band (AWS Console or
  `aws rds modify-db-instance --no-deletion-protection`) **before** approving
  the prod apply, or the destroy aborts.

The CI Terraform role keeps its `rds:Delete*` / `rds:CreateDBSnapshot` /
`DeleteDBSubnetGroup` / `DeleteDBParameterGroup` permissions through this apply
so the destroy (and the automatic final snapshot) succeed. Trimming those now-unused
permissions is deliberately deferred to a follow-up apply (tracked separately) to
avoid a self-modifying-policy race where the role removes its own delete
permission mid-apply.

## References

- [RDS Point-in-Time Recovery](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIT.html)
- Shared-RDS connectivity ADR: `docs/adr/0001-shared-rds-connectivity.md`
- Shared-RDS migration runbook: `docs/runbooks/shared-rds-migration.md`
- Incident triage: `docs/runbooks/incident-triage.md`
