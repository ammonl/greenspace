# greenspace_stack module

Composable Terraform module for all UN17 Village Rooftop Gardens AWS resources. Used by both
the staging and production environment stacks.

## Resources provisioned

| File             | Resources                                                  |
|------------------|------------------------------------------------------------|
| `networking.tf`  | Dedicated VPC (gated, retirable), public/private subnets, internet gateway, VPC endpoints, shared-VPC egress-only SG |
| `peering.tf`     | Optional VPC peering to the shared-RDS VPC (gated)         |
| `iam.tf`         | API runtime role, CI deploy role, CI Terraform role        |
| `ses.tf`         | SES configuration set (domain identity + DKIM owned by un17hub) |
| `dns.tf`         | No resources (Route 53 zone + SES/DKIM records owned by un17hub) |
| `monitoring.tf`  | CloudWatch log groups, SNS alarm topic, metric alarms, dashboard (alarms/dashboard gated), VPC flow logs (gated, retirable) |

## Shared-RDS connectivity

`peering.tf` provides an opt-in private path from the API Lambda to the
shared RDS instance owned by `ammonl/un17-infra-shared`. The peering is
gated on `shared_db_vpc_id` **and** on not being in shared-tenancy mode: when
`shared_db_vpc_id` is null (the default) or `shared_vpc_id` is set, no peering
resources are created (see [Shared-VPC tenancy](#shared-vpc-tenancy)). See
`docs/adr/0001-shared-rds-connectivity.md` for the full context.

To activate, set both inputs in the environment config:

```hcl
shared_db_vpc_id   = "vpc-xxxxxxxx"  # default VPC of the shared-db account
shared_db_vpc_cidr = "172.31.0.0/16" # CIDR of that VPC
```

The shared-db side must independently add its accepter-side route, RDS SG
ingress from the Greenspace VPC CIDR, and
`accepter.allow_remote_vpc_dns_resolution = true` for traffic to flow.

## Shared-VPC tenancy

When `shared_vpc_id` (and `shared_private_subnet_ids`) are set, the API Lambda
runs **inside the shared default VPC** owned by `ammonl/un17-infra-shared`
instead of this environment's dedicated VPC. This is the account-wide VPC
consolidation: greenspace has no dedicated database, so it is a networking-only
move.

In this mode the module:

- attaches the Lambda's `vpc_config` to `shared_private_subnet_ids` with a new
  egress-only security group (`aws_security_group.api_shared`) created in the
  shared VPC;
- does **not** create the dedicated VPC interface endpoints (SES + Secrets
  Manager) — those services are reached over the shared NAT gateway;
- tears down the shared-db peering — the shared RDS lives in the same VPC, so
  DB traffic stays internal and its security group already admits the shared VPC
  CIDR. Keep `shared_db_vpc_id`/`shared_db_vpc_cidr` **set** (not removed): the
  peering is gated off by tenancy mode, not by dropping the inputs, so that
  rollback recreates it in one step.

The dedicated VPC and subnets are left in place, dormant, as the rollback net.
Consume the shared VPC / subnet IDs from SSM at plan time — do not hardcode:

```hcl
data "aws_ssm_parameter" "shared_vpc_id" {
  name = "/shared/network/vpc-id"
}
data "aws_ssm_parameter" "shared_private_subnet_ids" {
  name = "/shared/network/private-subnet-ids"
}

module "greenspace_stack" {
  # ...
  shared_vpc_id             = nonsensitive(data.aws_ssm_parameter.shared_vpc_id.value)
  shared_private_subnet_ids = split(",", nonsensitive(data.aws_ssm_parameter.shared_private_subnet_ids.value))
}
```

The CI Terraform (plan) role reads these parameters via a scoped
`ssm:GetParameter`/`GetParameters` grant on
`arn:aws:ssm:*:*:parameter/shared/network/*` in the bootstrap policy.

To roll back, remove the two `shared_*` inputs: the Lambda moves back into the
dedicated VPC and the interface endpoints **and the shared-db peering** recreate
(the peering inputs were retained, so DB connectivity is restored in the same
apply). This rollback is only available while `retire_dedicated_vpc` is
`false` — see below.

## Dedicated VPC retirement

`retire_dedicated_vpc` destroys the dedicated VPC and everything that exists
only to serve it — subnets, route tables, the internet gateway, the
dedicated-VPC security groups (`aws_security_group.api` and `.db`), and VPC
flow logs (log group, IAM role, and the `aws_flow_log` itself). It is gated on
`shared_tenancy` being already active in **two** places: a `lifecycle
precondition` on `terraform_data.retire_dedicated_vpc_gate` fails the plan
loudly if `shared_vpc_id` is not set, and `local.dedicated_vpc_count` itself
requires both conditions — so a config mistake (`retire_dedicated_vpc = true`
without `shared_vpc_id`) can't silently strand the Lambda's only network path
even if the precondition were ever bypassed.

```hcl
retire_dedicated_vpc = true  # requires shared_vpc_id to already be set
```

There is no dedicated database to retire (greenspace has run on shared-db
since #347) and therefore no soak period: retire each environment as soon as
its shared-tenancy move (`shared_vpc_id` / `shared_private_subnet_ids`) has
validated. Staging and prod retire independently — this module has no
cross-environment state — with the actual apply ordering enforced by the
`terraform.yml` workflow (staging applies first; prod applies behind the
`production` GitHub environment's manual approval).

Retirement is otherwise a one-way door — reverting `retire_dedicated_vpc` to
`false` recreates a *fresh* dedicated VPC (new IDs), it does not restore the
destroyed one.

Module outputs that describe the dedicated VPC (`vpc_id`, `vpc_cidr`,
`db_security_group_id`) resolve to `null` once retired; `public_subnet_ids`
and `private_subnet_ids` resolve to empty lists.

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

## Log encryption

The CloudWatch log groups are encrypted at rest with an **AWS-owned** key: no
`kms_key_id` is set, which is CloudWatch's default. AWS-owned keys live outside
the account entirely — they are not the AWS-*managed* `aws/logs` key, they do
not appear in the KMS console, and they cost nothing.

The module used to provision a per-stack customer-managed key,
`aws_kms_key.logs`, for this. It was removed outright — key, alias, key policy,
and the `logs_kms_key_arn` output — rather than disassociated and left to age
out. **That made pre-existing log history unreadable**: events written before
the apply were encrypted under the key, and a key scheduled for deletion enters
`PendingDeletion` where it can no longer decrypt, so the loss landed on apply
rather than at the end of the deletion window. Up to 90 days of prod and 14 days
of staging API logs went with it. This was accepted deliberately. The only
recovery path is the 30-day `PendingDeletion` window: `aws kms
cancel-key-deletion` then `aws kms enable-key` restores readability while the
key still exists.

The SNS alarm topic sets no `kms_master_key_id` and is therefore **unencrypted
at rest**. This is deliberate, and `alias/aws/sns` is specifically not the fix.

Per the [SNS key management
docs](https://docs.aws.amazon.com/sns/latest/dg/sns-key-management.html), an AWS
service event source can publish to an encrypted topic **only** through a
customer-managed key whose policy names that service principal — and the
AWS-managed `alias/aws/sns` has no editable policy. CloudWatch alarms are this
topic's only publisher, so encrypting it that way would make every notification
undeliverable, silently: the alarm still transitions to ALARM, and the publish
just fails. A silent alerting failure is worse than the posture gap it buys.
The payload is an alarm name, a metric, and a state — no personal data. The
default topic policy (`AWS:SourceOwner` equal to the account) already admits
CloudWatch, so no compensating `aws_sns_topic_policy` is required.

**If you ever re-encrypt this topic, it needs a customer-managed key with an
`Allow_CloudWatch_for_CMK` statement.** Note the key this module used to have
never granted `cloudwatch.amazonaws.com` either — only account root and
`logs.<region>.amazonaws.com`, and account-root delegation reaches IAM
principals, not service principals acting as themselves. Alarm delivery through
an encrypted topic has therefore never worked in this stack. It has never
mattered, because `enable_alarms` is `false` in both environments and no topic
exists; but `var.enable_alarms` defaults to `true`, so the first season someone
turns alarms back on is the first time it would bite.

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
| `shared_vpc_id`               | Shared default VPC ID; non-null runs the Lambda in shared-tenancy mode |
| `shared_private_subnet_ids`   | Shared VPC private subnet IDs (required in tenancy mode) |
| `retire_dedicated_vpc`        | Destroys the dedicated VPC and its dependents; requires `shared_vpc_id` to already be set |
| `enable_alarms`               | Seasonal toggle for SNS topic + all CloudWatch alarms |
| `enable_dashboard`            | Toggle for the CloudWatch operational dashboard      |

See `variables.tf` for the full list with descriptions and defaults.

## Testing

```bash
terraform test  # Runs iam*.tftest.hcl (least-privilege validation) and retirement.tftest.hcl (retirement gate)
```
