# 0002 — Close the dedicated-VPC rollback path

Status: accepted
Date: 2026-07-30
Supersedes: [0001 — Greenspace runtime connectivity to shared RDS via VPC peering](0001-shared-rds-connectivity.md)

## Context

Greenspace's API Lambda runs in the shared default VPC owned by
`ammonl/un17-infra-shared` (#471), and each environment's dedicated VPC —
`10.0.0.0/16` staging, `10.1.0.0/16` prod — was destroyed once that move
validated (#472).

The Terraform configuration for those VPCs did not go with them. The module
still declared `aws_vpc.main`, both subnet sets, both route tables, the internet
gateway, the interface endpoints, the dedicated-VPC security groups, the VPC
flow logs, and all of `peering.tf`, held at `count = 0` behind
`retire_dedicated_vpc` / `local.dedicated_vpc_count`. The module README
documented reverting that gate as a supported, discouraged rollback.

Keeping the configuration had a cost beyond the dead code. The CI Terraform role
is scoped to what the module can apply, so its `VPCNetworking` statement granted
49 EC2 actions — the full VPC lifecycle, subnets, gateways, endpoints, route
tables, flow logs, and the complete VPC peering set — to keep a rollback
appliable that nobody intends to use.

Two facts decided it:

- **The rollback was already a one-way door.** Reverting the gate recreates a
  *fresh* dedicated VPC with new ids and a new CIDR; it does not restore the
  destroyed one. What the retained configuration and grants bought was the
  ability to stand up a new dedicated VPC — a fresh build, not a recovery.
- **The peering half could not have worked at all.** The shared-tenancy path
  reaches the shared RDS over the shared VPC's internal network with no peering
  hop, and `un17-infra-shared` has dropped its accepter-side grants
  (ammonl/un17-infra-shared#93). There is no peer left on the other side to
  connect to.

## Decision

Delete the dedicated-VPC configuration outright and prune the CI Terraform role
to the surface that remains. The shared VPC is the only runtime network, and
`shared_vpc_id` / `shared_private_subnet_ids` become required module inputs
rather than a mode selector.

Concretely:

- `networking.tf` keeps only the egress-only security group the Lambda runs
  behind in the shared VPC, and its egress rule — unconditional, no longer
  gated. Everything else in that file is gone, along with the interface
  endpoints (SES, Secrets Manager) that only ever existed to serve a VPC with no
  NAT of its own.
- `peering.tf` is deleted. So is `retire_dedicated_vpc`, its plan-time
  precondition gate (`terraform_data.retire_dedicated_vpc_gate`), the
  `shared_tenancy` / `peering_enabled` / `dedicated_vpc_count` locals, the
  dedicated-VPC input variables, and the module outputs that described the
  destroyed resources.
- VPC flow logs are gone from `monitoring.tf`. The shared VPC's owner owns its
  flow logs.
- The role's `VPCNetworking` statement becomes `SharedVpcSecurityGroup`: the
  security-group lifecycle, its tags, and the four reads that resolve the
  Lambda's `vpc_config` — 13 actions where there were 49. The `sid` is renamed
  because the old one overstated the scope even before this change.
- `iam.tftest.hcl` gains an allowlist assert over every `ec2:` action the role
  is granted in an `Allow` statement, ported from `ammonl/un17-resources`. An
  allowlist rather than a denylist on purpose: the regex-shaped guard it
  replaces let a bare `ec2:*` — the broadest grant possible — pass silently, and
  an allowlist closes wildcards and unenumerated actions in the same assert.

The security-group ingress pair (`AuthorizeSecurityGroupIngress`,
`RevokeSecurityGroupIngress`) is dropped with the rest. The role's CloudTrail
history shows it using both, but against the dedicated-VPC DB security group
during the retirement applies — that group no longer exists, and nothing in the
configuration declares an ingress rule any more. `ec2:ModifySecurityGroupRules`
is deliberately *not* added, though `un17-resources` grants it: it is what an
in-place edit of an existing egress rule needs, nothing here edits one, and on
the wildcard resource it can rewrite ingress rules on groups this repo does not
own.

## Alternatives considered

### Keep the rollback path, prune only the peering set

Hold `retire_dedicated_vpc` open and drop only the five peering actions, which
are dead under either choice.

Rejected because it preserves the more expensive half of the problem — 44 EC2
grants and roughly 250 lines of `count = 0` configuration — to keep an escape
hatch that cannot restore anything. A fresh dedicated VPC can be rebuilt from
git history if the shared-VPC model is ever abandoned; that is a project, not a
rollback, and it should not be paid for continuously in standing permissions.

### Prune the grants, keep the configuration

Drop the EC2 grants but leave the gated resources in place as documentation of
the old topology.

Rejected because it produces a configuration that cannot apply what it declares.
The gate would look revertible and fail on `AccessDenied` mid-apply — worse than
either honest end of the trade.

### Keep the grants, delete the configuration

Rejected for the same reason in reverse: permissions with nothing to apply them
to are exactly the leftover this ticket exists to clear.

## Consequences

- **The shared-VPC move is no longer reversible by configuration.** Reverting it
  now means restoring the deleted resources from git history, choosing fresh
  CIDRs, and reapplying — and, because the CI Terraform role is defined by the
  stack it applies, granting the VPC-lifecycle permissions out of band first
  (`aws iam put-role-policy --role-name <naming_prefix>-ci-terraform
  --policy-name <distinct-temporary-name>`, see the note in `iam.tf`) so the
  plan that reintroduces them can run. This cost is accepted deliberately.
- The CI Terraform role's EC2 surface drops from 49 actions to 13, and can no
  longer create a VPC, subnet, gateway, endpoint, route, flow log, or peering
  connection in this account.
- ADR 0001's peering model is fully retired: no peering resources, no peering
  grants, no `shared_db_vpc_id` / `shared_db_vpc_cidr` inputs. The accepter-side
  cleanup in `un17-infra-shared` is tracked there.
- `shared_vpc_id` and `shared_private_subnet_ids` are required inputs. An
  environment that omits them fails at plan time on variable validation instead
  of silently falling back to a dedicated VPC — which is the honest outcome now
  that there is no fallback to fall back to.
- Module outputs `vpc_id`, `vpc_cidr`, `public_subnet_ids`, `private_subnet_ids`,
  `db_security_group_id`, and `shared_db_peering_connection_id` are removed, as
  is the `vpc_id` output from both environment roots. Nothing outside this repo
  consumed them; the shared-db side stopped needing `vpc_cidr` when the peering
  came down.
- No AWS resource changes. Everything deleted here was already at `count = 0` in
  both environments' state, so it had no live instances to destroy. The two
  resources that survive — the shared-VPC security group and its egress rule —
  lost their `count`, which renames their state addresses from `[0]` to
  unindexed; `moved` blocks in `networking.tf` carry the existing instances
  across so Terraform does not replace the security group the running Lambda is
  attached to. The only planned destroy is
  `terraform_data.retire_dedicated_vpc_gate`, a state-only resource that touches
  nothing in AWS.
