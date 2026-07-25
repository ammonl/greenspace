# greenspace_stack module

Composable Terraform module for all UN17 Village Rooftop Gardens AWS resources. Used by both
the staging and production environment stacks.

## Resources provisioned

| File             | Resources                                                  |
|------------------|------------------------------------------------------------|
| `networking.tf`  | VPC, public/private subnets, internet gateway, VPC endpoints |
| `peering.tf`     | Optional VPC peering to the shared-RDS VPC (gated)         |
| `iam.tf`         | API runtime role, CI deploy role, CI Terraform role        |
| `ses.tf`         | SES domain identity, DKIM, configuration set               |
| `dns.tf`         | Route 53 hosted zone, SES verification/DKIM DNS records    |
| `monitoring.tf`  | CloudWatch log groups, KMS encryption key, SNS alarm topic, metric alarms, dashboard (alarms/dashboard gated) |

## Shared-RDS connectivity

`peering.tf` provides an opt-in private path from the API Lambda to the
shared RDS instance owned by `ammonlarson/infra-shared-db`. The peering is
gated on `shared_db_vpc_id`: when null (the default), no peering resources
are created. See `docs/adr/0001-shared-rds-connectivity.md` for the full
context.

To activate, set both inputs in the environment config:

```hcl
shared_db_vpc_id   = "vpc-xxxxxxxx"  # default VPC of the shared-db account
shared_db_vpc_cidr = "172.31.0.0/16" # CIDR of that VPC
```

The shared-db side must independently add its accepter-side route, RDS SG
ingress from the Greenspace VPC CIDR, and
`accepter.allow_remote_vpc_dns_resolution = true` for traffic to flow.

## Monitoring & seasonal alarms

CloudWatch log groups and VPC flow logs are always provisioned. The SNS alarm
topic, its email subscription, and all CloudWatch metric alarms are gated by
`enable_alarms`; the operational dashboard is gated by `enable_dashboard`.

Alarms are **seasonal**: the platform only runs an active registration window
for part of the year, so alarms are turned off out of season to avoid noise and
cost. Both staging and prod currently set `enable_alarms = false`. To re-enable
alarms for an active season, flip the single flag in the environment config
(`environments/<env>/main.tf`) to `true` — no per-alarm edits are required:

```hcl
enable_alarms = true
```

`alarm_email` can stay set while alarms are disabled; it is ignored until
`enable_alarms` is `true`.

## Least-privilege IAM

SES send permissions are scoped to SES identities in this account and region
(`identity/*`). The domain identity itself is owned by the un17hub repository
(see below), so it is not a module-managed resource; the identity-ARN pattern
keeps the runtime role's send scope tight without depending on it.

## SES email configuration

The SES **domain identity and DKIM signing** for `un17hub.com` — which, via
SES parent-domain verification, also authorizes sending from the
`staging.un17hub.com` subdomain — are owned by the **un17hub repository**,
alongside the `un17hub.com` hosted zone that publishes their DNS records. This
module provisions only its own per-environment **configuration set** and sends
from `greenspace@<ses_sender_domain>` against that externally-verified identity.
Sender addresses default to `greenspace@<ses_sender_domain>` and can be
overridden via `ses_sender_email`. Reply-To defaults to `elise7284@gmail.com`
(spec default) and can be overridden via `ses_reply_to_email`.

| Environment | Domain                 | Sender address                        | Reply-To                |
|-------------|------------------------|---------------------------------------|-------------------------|
| staging     | `staging.un17hub.com`  | `greenspace@staging.un17hub.com`      | `elise7284@gmail.com`   |
| prod        | `un17hub.com`          | `greenspace@un17hub.com`              | `elise7284@gmail.com`   |

### DNS verification

The `un17hub.com` hosted zone (and the `staging.un17hub.com` subdomain folded
into it) is managed by the un17hub repository, which also publishes the SES
domain-verification TXT record and DKIM CNAMEs. This module manages no Route 53
zone or records; SES verification and DKIM are handled by that repository once
its records propagate.

## Key variables

| Variable                      | Description                                          |
|-------------------------------|------------------------------------------------------|
| `environment`                 | Deployment environment name (staging, prod)          |
| `vpc_cidr`                    | CIDR block for the VPC                               |
| `ses_sender_domain`           | Sender domain / Amplify custom domain (SES identity + zone owned by un17hub repo) |
| `ses_reply_to_email`          | Default Reply-To (defaults to `elise7284@gmail.com`) |
| `shared_db_vpc_id`            | Shared-RDS VPC ID; null disables peering             |
| `shared_db_vpc_cidr`          | Shared-RDS VPC CIDR (required when peering enabled)  |
| `enable_alarms`               | Seasonal toggle for SNS topic + all CloudWatch alarms |
| `enable_dashboard`            | Toggle for the CloudWatch operational dashboard      |

See `variables.tf` for the full list with descriptions and defaults.

## Testing

```bash
terraform test  # Runs iam.tftest.hcl (least-privilege validation)
```
