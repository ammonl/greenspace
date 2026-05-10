# greenspace_stack module

Composable Terraform module for all UN17 Village Rooftop Gardens AWS resources. Used by both
the staging and production environment stacks.

## Resources provisioned

| File             | Resources                                                  |
|------------------|------------------------------------------------------------|
| `networking.tf`  | VPC, public/private subnets, internet gateway, VPC endpoints |
| `peering.tf`     | Optional VPC peering to the shared-RDS VPC (gated)         |
| `iam.tf`         | API runtime role, CI deploy role, CI Terraform role        |
| `database.tf`    | RDS PostgreSQL instance, subnet group, Secrets Manager     |
| `ses.tf`         | SES domain identity, DKIM, configuration set               |
| `dns.tf`         | Route 53 hosted zone, SES verification/DKIM DNS records    |
| `monitoring.tf`  | CloudWatch log groups, KMS encryption key                  |

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

## Least-privilege IAM

SES send permissions are scoped to the SES domain identity provisioned by the
module (`aws_ses_domain_identity`). Wildcard (`*`) resources are not accepted
where resource-level scoping is possible.

## SES email configuration

Each environment provisions its own SES domain identity, DKIM signing, and
configuration set. Sender addresses default to `greenspace@<ses_sender_domain>`
and can be overridden via `ses_sender_email`. Reply-To defaults to
`elise7284@gmail.com` (spec default) and can be overridden via
`ses_reply_to_email`.

| Environment | Domain                 | Sender address                        | Reply-To                |
|-------------|------------------------|---------------------------------------|-------------------------|
| staging     | `staging.un17hub.com`  | `greenspace@staging.un17hub.com`      | `elise7284@gmail.com`   |
| prod        | `un17hub.com`          | `greenspace@un17hub.com`              | `elise7284@gmail.com`   |

### DNS verification

Route 53 hosted zones and DNS records for SES domain verification and DKIM
are managed by Terraform. After the first `terraform apply`:

1. **Point your registrar's nameservers** to the Route 53 zone nameservers
   (output: `route53_nameservers`).
2. **Delegate the staging subdomain** by adding an NS record in the prod
   Route 53 zone for `staging.un17hub.com` pointing to the staging zone's
   nameservers.
3. SES will verify the domain and enable DKIM signing automatically once DNS
   propagates.

## Key variables

| Variable                      | Description                                          |
|-------------------------------|------------------------------------------------------|
| `environment`                 | Deployment environment name (staging, prod)          |
| `vpc_cidr`                    | CIDR block for the VPC                               |
| `ses_sender_domain`           | Domain for SES identity and Route 53 zone            |
| `ses_reply_to_email`          | Default Reply-To (defaults to `elise7284@gmail.com`) |
| `db_instance_class`           | RDS instance class                                   |
| `shared_db_vpc_id`            | Shared-RDS VPC ID; null disables peering             |
| `shared_db_vpc_cidr`          | Shared-RDS VPC CIDR (required when peering enabled)  |

See `variables.tf` for the full list with descriptions and defaults.

## Testing

```bash
terraform test  # Runs iam.tftest.hcl (least-privilege validation)
```
