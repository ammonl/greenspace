# ---------- Shared default VPC (consumed as module inputs) ----------
#
# The API Lambda runs in the shared default VPC owned by
# `ammonl/un17-infra-shared` rather than a per-environment VPC. The environment
# roots read the shared VPC id and its private egress subnet ids from the SSM
# tenancy contract at plan time and pass them in as `shared_vpc_id` /
# `shared_private_subnet_ids`.
#
# The shared RDS security group already admits the shared-VPC CIDR, so the DB
# path needs no peering and no per-environment DB security group. SES and
# Secrets Manager egress rides the shared NAT — tenants must not create VPC
# endpoints or NAT resources in the shared VPC.

# ---------- Lambda Security Group ----------
#
# The only network resource this module creates in the shared VPC. Ingress is
# never needed because the Lambda is only ever an initiator: it reaches the
# shared RDS, Secrets Manager, and SES outbound, and nothing dials it back.

resource "aws_security_group" "api_shared" {
  name_prefix = "${local.naming_prefix}-api-shared-"
  description = "Egress-only security group for the API Lambda in the shared VPC"
  vpc_id      = var.shared_vpc_id

  tags = {
    Name = "${local.naming_prefix}-api-shared-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "api_shared_all_outbound" {
  security_group_id = aws_security_group.api_shared.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Both resources above were gated on the shared-tenancy mode that is now the only
# mode, so they lost their `count`. Dropping it renames their state addresses from
# `[0]` to unindexed, which Terraform would otherwise plan as a destroy and
# recreate — replacing the security group the running Lambda is attached to. These
# keep the existing instances in place; the apply stays a no-op.
moved {
  from = aws_security_group.api_shared[0]
  to   = aws_security_group.api_shared
}

moved {
  from = aws_vpc_security_group_egress_rule.api_shared_all_outbound[0]
  to   = aws_vpc_security_group_egress_rule.api_shared_all_outbound
}
