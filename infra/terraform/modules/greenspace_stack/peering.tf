# ---------- Shared-RDS VPC Peering ----------
#
# Provides a private network path from the API Lambda (in this VPC's private
# subnets) to the shared RDS instance owned by `ammonlarson/infra-shared-db`.
# The shared RDS lives in that account's default VPC; we create a peering
# connection per Greenspace environment so staging and prod fail
# independently.
#
# Gated on `var.shared_db_vpc_id`: when null (the default), no peering
# resources are created and the apply is a no-op. The variable is set in the
# environment configs once the shared-db side has provisioned the route +
# RDS SG ingress documented in `docs/adr/0001-shared-rds-connectivity.md`.
#
# `auto_accept = true` works because both VPCs live in the same AWS account
# and region (validated by the same-account assumption baked into the
# CI Terraform IAM scoping). The accepter-side route, RDS SG ingress, and
# `accepter.allow_remote_vpc_dns_resolution` are owned by the shared-db
# repo so each side manages its own VPC's resources.

resource "aws_vpc_peering_connection" "shared_db" {
  count = var.shared_db_vpc_id == null ? 0 : 1

  vpc_id      = aws_vpc.main.id
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
  count = var.shared_db_vpc_id == null ? 0 : 1

  vpc_peering_connection_id = aws_vpc_peering_connection.shared_db[0].id

  requester {
    allow_remote_vpc_dns_resolution = true
  }
}

resource "aws_route" "private_to_shared_db" {
  count = var.shared_db_vpc_id == null ? 0 : 1

  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = var.shared_db_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_db[0].id
}
