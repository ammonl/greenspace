# greenspace_stack module

Composable Terraform module for all UN17 Village Rooftop Gardens AWS resources. Used by both
the staging and production environment stacks.

## Resources provisioned

| File             | Resources                                                  |
|------------------|------------------------------------------------------------|
| `networking.tf`  | Egress-only API Lambda security group in the shared VPC    |
| `iam.tf`         | API runtime role, CI deploy role, CI Terraform role        |
| `ses.tf`         | SES configuration set (domain identity + DKIM owned by un17hub) |
| `dns.tf`         | No resources (Route 53 zone + SES/DKIM records owned by un17hub) |
| `monitoring.tf`  | CloudWatch log group, SNS alarm topic, metric alarms, dashboard (alarms/dashboard gated), module-wide `aws_caller_identity` / `aws_region` data sources |

## Shared-VPC tenancy

The API Lambda runs **inside the shared default VPC** owned by
`ammonl/un17-infra-shared`. This is the account-wide VPC consolidation:
greenspace has no dedicated database, so it was a networking-only move.

The module:

- attaches the Lambda's `vpc_config` to `shared_private_subnet_ids` with an
  egress-only security group (`aws_security_group.api_shared`) created in the
  shared VPC — the only network resource it owns there;
- creates **no** VPC interface endpoints: SES and Secrets Manager are reached
  over the shared NAT gateway, and tenants must not create endpoints in the
  shared VPC;
- needs **no** peering for the DB path: the shared RDS lives in the same VPC, so
  DB traffic stays internal and its security group already admits the shared VPC
  CIDR.

`shared_vpc_id` and `shared_private_subnet_ids` are **required** — there is no
dedicated VPC to fall back to (see [Dedicated VPC
retirement](#dedicated-vpc-retirement)), so omitting either fails at plan time
on variable validation rather than silently leaving the Lambda without a network
path. Consume them from SSM at plan time — do not hardcode:

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

## Dedicated VPC retirement

Each environment used to run the API Lambda in its own VPC (`10.0.0.0/16`
staging, `10.1.0.0/16` prod), with private subnets, an internet gateway, SES and
Secrets Manager interface endpoints, its own security groups, VPC flow logs, and
a peering connection to the shared-RDS VPC. All of it was destroyed once the
shared-tenancy move validated in each environment.

The retirement ran behind a `retire_dedicated_vpc` gate, which left the destroyed
resources declared at `count = 0` and a revert documented as supported. **That
rollback path is now closed** — the gated resources, `peering.tf`, the gate
variable and its precondition, the dedicated-VPC inputs, and the outputs
describing the destroyed resources are deleted. See
`docs/adr/0002-close-dedicated-vpc-rollback-path.md` for the decision, and
`docs/adr/0001-shared-rds-connectivity.md` for the superseded peering model.

Reverting the gate would only ever have built a *fresh* dedicated VPC with new
ids and a new CIDR, not restored the destroyed one, and the peering half could
not have worked at all once `un17-infra-shared` dropped its accepter-side grants.
Undoing the shared-VPC move now means restoring the deleted resources from git
history, choosing fresh CIDRs, and — because the CI Terraform role is defined by
the stack it applies — granting the VPC-lifecycle permissions out of band before
the plan that reintroduces them can run (see the note in `iam.tf`).

## Monitoring & seasonal alarms

The API CloudWatch log group is always provisioned. The SNS alarm topic, its
email subscription, and all CloudWatch metric alarms are gated by
`enable_alarms`; the operational dashboard is gated by `enable_dashboard`.

VPC flow logs are not provisioned — the shared VPC is owned by
`ammonl/un17-infra-shared`, which owns its flow logs too.

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
`aws_kms_key.logs`, for this. It is removed outright — key, alias, key policy,
and the `logs_kms_key_arn` output — rather than disassociated and left to age
out. **Applying that removal makes pre-existing log history unreadable** in the
environment it applies to: events written before the apply are encrypted under
the key, and a key scheduled for deletion enters `PendingDeletion` where it can
no longer decrypt, so the loss lands on apply rather than at the end of the
deletion window. Up to 90 days of prod and 14 days of staging API logs go with
it. This was accepted deliberately. Staging and prod apply separately —
`terraform.yml` applies staging on merge and gates prod behind the `production`
environment's manual approval — so one may have lost its history while the other
still has it.

Recovery is possible for 30 days after the apply, but **it takes three steps,
not two.** The same apply destroys `aws_kms_key_policy.logs`, and destroying
that resource does not delete the policy — the provider resets it to the
account default, which is root-only. Cancelling the deletion therefore leaves an
enabled key that CloudWatch Logs still cannot use, because account-root
delegation reaches IAM principals, not service principals acting as themselves.
The policy has to be put back:

```
aws kms cancel-key-deletion --key-id <key-arn>
aws kms enable-key          --key-id <key-arn>
aws kms put-key-policy      --key-id <key-arn> --policy-name default \
  --policy file://logs-key-policy.json
```

where `logs-key-policy.json` re-grants `logs.<region>.amazonaws.com` at minimum
`kms:Decrypt` and `kms:DescribeKey`, under the original `ArnLike` condition on
`kms:EncryptionContext:aws:logs:arn` scoped to `log-group:/<naming_prefix>/*`.
The CI Terraform role cannot run any of this — `iam.tf` grants it none of
`kms:CancelKeyDeletion`, `kms:EnableKey`, or `kms:PutKeyPolicy`, so recovery
needs an admin principal. The key ARNs are recorded on the follow-up ticket,
since the apply deletes the aliases and removes the output.

Note also that each of those applies dropped log events for a few seconds.
Terraform orders the KMS destroys **before** the in-place update that
disassociates the log group, so between the key policy reset and the
`DisassociateKmsKey` call `PutLogEvents` was denied. The apply did not fail, and
out of season the gap was probably empty, but new events in that window are lost.

With the removal applied in both environments, the CI Terraform role's grants
that existed only to manage the key are gone as well: the whole key-lifecycle
set, plus `logs:AssociateKmsKey` / `logs:DisassociateKmsKey`. `kms:Decrypt`
stays, because the environment roots read the shared-VPC tenancy contract from
SSM on every plan and a `SecureString` under a customer-managed key would need
it — see the comment on the `KMSDecrypt` statement in `iam.tf` for the three
commands that settle whether it is still load-bearing.

`log_encryption.tftest.hcl` guards that posture across **all three** inline
policies on the role — `terraform-state`, `terraform-resources`, and
`terraform-resources-bootstrap` — because IAM unions them, so a guard that reads
one document proves nothing about the role. It caps the granted `kms:` set at
`kms:Decrypt` plus the bootstrap policy's `Describe*`/`Get*`/`List*` reads,
rejects both `logs:` key-binding actions, rejects a bare `*` or a `service:*`
wildcard that would confer either without naming it, and — in the other
direction — requires `kms:Decrypt` to still be there. That last one is not
symmetry for its own sake: an apply can always remove a grant, but a role that
has lost the permission its own plan depends on cannot restore it.

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

The CI Terraform role's EC2 surface is limited to the one network resource this
module owns in the shared VPC: the `SharedVpcSecurityGroup` statement grants the
security-group lifecycle, its tags, and the four reads that resolve the Lambda's
`vpc_config` — nothing that could create a VPC, subnet, gateway, endpoint,
route, flow log, or peering connection. `iam.tftest.hcl` asserts the granted
`ec2:` set against an explicit allowlist rather than denying known-bad actions,
so a wildcard (`ec2:*`) or an action nobody thought to name fails too. Widen the
allowlist deliberately, in the same change as the resource that needs it.

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
| `ses_sender_domain`           | Sender domain / Amplify custom domain (SES identity + zone owned by un17hub repo) |
| `ses_reply_to_email`          | Default Reply-To (defaults to `elise7284@gmail.com`) |
| `shared_vpc_id`               | Shared default VPC ID the Lambda runs in (required)  |
| `shared_private_subnet_ids`   | Shared VPC private subnet IDs (required, non-empty)  |
| `enable_alarms`               | Seasonal toggle for SNS topic + all CloudWatch alarms |
| `enable_dashboard`            | Toggle for the CloudWatch operational dashboard      |

See `variables.tf` for the full list with descriptions and defaults.

## Testing

```bash
terraform test  # Runs iam*.tftest.hcl (least-privilege + CI policy drift guards)
```
