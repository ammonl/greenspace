# ---------- Shared-RDS VPC Peering ----------
#
# Provides a private network path from the API Lambda (in this VPC's private
# subnets) to the shared RDS instance owned by `ammonl/un17-infra-shared`.
# The shared RDS lives in that account's default VPC; we create a peering
# connection per Greenspace environment so staging and prod fail
# independently.
#
# Gated on `local.peering_enabled` (`var.shared_db_vpc_id` set AND not in
# shared-tenancy mode): when null (the default), no peering resources are
# created and the apply is a no-op. The variable is set in the environment
# configs once the shared-db side has provisioned the route + RDS SG ingress
# documented in `docs/adr/0001-shared-rds-connectivity.md`. In shared-tenancy
# mode the peering is torn down — the Lambda reaches the shared RDS directly
# inside the shared VPC — while the inputs stay set so reverting `shared_vpc_id`
# recreates it.
#
# `auto_accept = true` works because both VPCs live in the same AWS account
# and region (per the same-account assumption documented in the ADR; the
# CI Terraform IAM scoping does not enforce it). The accepter-side route,
# RDS SG ingress, and `accepter.allow_remote_vpc_dns_resolution` are owned
# by the shared-db repo so each side manages its own VPC's resources.

resource "aws_vpc_peering_connection" "shared_db" {
  count = local.peering_enabled ? 1 : 0

  vpc_id      = aws_vpc.main[0].id
  peer_vpc_id = var.shared_db_vpc_id
  auto_accept = true

  tags = {
    Name = "${local.naming_prefix}-shared-db-peering"
  }

  lifecycle {
    precondition {
      condition     = var.shared_db_vpc_cidr != null
      error_message = "shared_db_vpc_cidr must be provided when shared_db_vpc_id is set; the private route table needs a destination CIDR for the peering route."
    }
  }
}

# Enable DNS resolution from this VPC across the peering so the shared RDS
# endpoint hostname resolves to a private IP for queries originating here.
# Without this, the public DNS would resolve to a public IP and the traffic
# would not take the peering route.
resource "aws_vpc_peering_connection_options" "shared_db" {
  count = local.peering_enabled ? 1 : 0

  vpc_peering_connection_id = aws_vpc_peering_connection.shared_db[0].id

  requester {
    allow_remote_vpc_dns_resolution = true
  }
}

resource "aws_route" "private_to_shared_db" {
  count = local.peering_enabled ? 1 : 0

  route_table_id            = aws_route_table.private[0].id
  destination_cidr_block    = var.shared_db_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_db[0].id
}
