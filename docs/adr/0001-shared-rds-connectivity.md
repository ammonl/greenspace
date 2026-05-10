# 0001 — Greenspace runtime connectivity to shared RDS via VPC peering

Status: accepted
Date: 2026-05-10

## Context

Greenspace runs its API as a Lambda inside a per-environment VPC
(`10.0.0.0/16` staging, `10.1.0.0/16` prod). The function is attached to
private subnets only. NAT Gateways were removed in #324 because the only AWS
calls Lambda made from inside the VPC (SES `SendEmail`, Secrets Manager
`GetSecretValue`) could be served by interface endpoints at roughly a tenth of
the NAT cost. The private route table therefore has no `0.0.0.0/0` route at
all today.

In parallel, Greenspace is migrating off its dedicated per-environment RDS
onto the shared RDS owned by `ammonlarson/infra-shared-db`. After #339 the
shared instance exposes two distinct projects — `greenspace_staging` and
`greenspace_prod` — each with its own database, role, and Secrets Manager
secret. The shared instance currently has `publicly_accessible = true` and a
security group that allows ingress only from a curated `allowed_ingress_cidrs`
list (the operator's `/32`, used to apply schema-level Terraform from a
laptop because the `cyrilgdn/postgresql` provider needs to dial Postgres).

So Lambda has IAM access wired through #339 but no actual network path to
Postgres: it cannot reach the public endpoint (no NAT egress) and it cannot
reach the private one (no peering). This ADR records the connectivity model
we adopt to close that gap.

## Decision

Use **VPC peering** between each Greenspace VPC and the shared-db default
VPC, with `requester.allow_remote_vpc_dns_resolution = true` enabled on the
Greenspace side so the shared RDS endpoint name resolves to a private address
for queries originating inside the peered Greenspace VPC.

Concretely:

- The Greenspace `greenspace_stack` Terraform module owns the **requester**
  side: the `aws_vpc_peering_connection` (with `auto_accept = true`, valid
  because both VPCs live in the same AWS account and region), the
  `aws_vpc_peering_connection_options` block that turns on remote-VPC DNS
  resolution from the requester, and the route in each Greenspace private
  route table that sends the shared-db CIDR to the peering connection.
- These resources are gated behind a `shared_db_vpc_id` module input. When
  the variable is `null` the resources are not created, so the module
  remains apply-clean while the shared-db side catches up.
- The shared-db repo owns the **accepter** side: a route from its default
  VPC to the Greenspace VPC CIDR via the peering connection, an ingress rule
  on the shared RDS security group that allows `tcp/5432` from the
  Greenspace VPC CIDR, and the matching
  `accepter.allow_remote_vpc_dns_resolution = true` option. None of those
  changes are made in this ADR's PR; they ship in a follow-up
  `infra-shared-db` PR.
- One peering connection is created **per Greenspace environment**, so
  staging and prod stay isolated and fail independently.
- The shared RDS keeps its current `publicly_accessible = true` posture and
  the operator `/32` allowlist. We do not broaden ingress: the only new
  permitted source is the Greenspace VPC CIDR via the peering connection,
  which is private routing on the AWS backbone.

## Alternatives considered

### NAT Gateway + Elastic IP allowlist

Re-add a NAT Gateway in each Greenspace VPC, allocate a static EIP, and
have shared-db append those two `/32`s to `allowed_ingress_cidrs`.

Rejected because:

- Reintroduces the cost #324 deliberately removed (~$32–65/mo per
  environment depending on AZ count and bytes).
- Pins the runtime model to public-internet egress for every future
  shared-account dependency, instead of moving toward private routing.
- The shared RDS has to remain `publicly_accessible = true` permanently to
  serve Lambda traffic, which makes a future "lock down to private" move
  harder.

It is the simplest model and remains a fallback if peering ever proves
unworkable, but on cost and direction-of-travel it is the worse choice.

### PrivateLink (NLB → VPC endpoint service)

Have shared-db front the RDS with a Network Load Balancer, publish an
endpoint service, and have Greenspace create an interface endpoint per
environment.

Rejected because:

- Requires significant new infrastructure on the shared-db side (NLB,
  target group health checks against RDS, endpoint service) for two
  consumers.
- Endpoint service hourly + per-GB charges are higher than peering's
  per-GB-only charges at our traffic levels.
- It is a defensible end-state once the consumer count grows, but
  premature today.

### Transit Gateway

Attach both VPCs to a TGW.

Rejected because:

- TGW attachment hourly cost (~$36/mo per attachment) plus per-GB charges
  is materially worse than peering for two VPCs.
- Adds an account-wide resource neither team needs yet.
- The "transit" value (any-to-any across many VPCs) doesn't apply at this
  fan-out.

### Move shared RDS into a private subnet of a non-default VPC, then peer

The cleanest end-state, but it conflates two changes. Out of scope for this
ticket; can happen later inside `infra-shared-db` without changing the
Greenspace side.

## Consequences

- Greenspace VPCs gain one peering connection each. Greenspace private
  route tables gain one extra route (to the shared-db CIDR). The Lambda
  security group does not need to change — it already permits all egress.
- The shared RDS does not need a public-internet path from Greenspace,
  which keeps the `allowed_ingress_cidrs` list tight (operator `/32` plus
  Greenspace VPC CIDRs added on the shared-db side).
- The CI Terraform role gains a small set of EC2 peering verbs
  (`CreateVpcPeeringConnection`, `AcceptVpcPeeringConnection`,
  `ModifyVpcPeeringConnectionOptions`,
  `DeleteVpcPeeringConnection`, plus `Describe*PeeringConnection*` covered
  by the bootstrap policy). These are scoped to the same account.
- Cross-repo coordination is required: until the shared-db PR lands, the
  Greenspace `shared_db_vpc_id` input stays null and the peering resources
  do not exist. Day-one staging/prod apply remains unchanged.
- Validation: once both sides are applied, an operator-run smoke test
  (`psql -h <shared-rds-endpoint> -U greenspace_<env>_app -d
  greenspace_<env> -c 'select 1'` invoked via `aws lambda invoke` against
  a one-shot Lambda payload that opens a TCP socket to `:5432`) confirms
  connectivity per environment.
- Direction of travel: if the shared-db RDS is moved into a private
  subnet later, no Greenspace-side change is required. If shared-db
  switches to PrivateLink later, peering can be retired.
