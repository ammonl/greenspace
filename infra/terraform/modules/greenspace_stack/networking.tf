# ---------- VPC ----------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.naming_prefix}-vpc"
  }
}

# ---------- Internet Gateway ----------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.naming_prefix}-igw"
  }
}

# ---------- Public Subnets ----------

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.naming_prefix}-public-${var.availability_zones[count.index]}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.naming_prefix}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------- Private Subnets ----------

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.naming_prefix}-private-${var.availability_zones[count.index]}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.naming_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------- Security Groups ----------

resource "aws_security_group" "api" {
  name_prefix = "${local.naming_prefix}-api-"
  description = "Security group for API Lambda functions"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.naming_prefix}-api-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "api_all_outbound" {
  security_group_id = aws_security_group.api.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Egress-only security group for the API Lambda when it runs in the shared VPC
# (shared-tenancy mode). It lives in the shared VPC — not this environment's
# dedicated VPC — and only allows outbound: reaching the shared RDS, Secrets
# Manager and SES via the shared NAT, plus external egress. Ingress is never
# needed because the Lambda is only ever an initiator. Tenants must not create
# interface endpoints in the shared VPC.
resource "aws_security_group" "api_shared" {
  count = local.shared_tenancy ? 1 : 0

  name_prefix = "${local.naming_prefix}-api-shared-"
  description = "Egress-only security group for the API Lambda in the shared VPC"
  vpc_id      = var.shared_vpc_id

  tags = {
    Name = "${local.naming_prefix}-api-shared-sg"
  }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length(var.shared_private_subnet_ids) > 0
      error_message = "shared_private_subnet_ids must be non-empty when shared_vpc_id is set; the Lambda vpc_config needs subnets in the shared VPC."
    }
  }
}

resource "aws_vpc_security_group_egress_rule" "api_shared_all_outbound" {
  count = local.shared_tenancy ? 1 : 0

  security_group_id = aws_security_group.api_shared[0].id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "db" {
  name_prefix = "${local.naming_prefix}-db-"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.naming_prefix}-db-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_api" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from API security group"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.api.id
}

# ---------- VPC Interface Endpoints ----------
#
# The API Lambda runs inside private subnets with no default route to the
# internet. Calls it makes from inside the function (SES SendEmail, Secrets
# Manager GetSecretValue) need a path to the corresponding AWS service. Each
# Interface endpoint costs ~$7/mo per AZ versus ~$36/mo for a NAT Gateway +
# EIP, and keeps traffic on the AWS backbone. CloudWatch Logs for Lambda are
# pushed by the Lambda service itself, not from inside the VPC, so no Logs
# endpoint is required.
#
# Not created in shared-tenancy mode: there the Lambda reaches SES and Secrets
# Manager over the shared NAT, and tenants must not create endpoints in the
# shared VPC.

resource "aws_security_group" "vpc_endpoints" {
  count = local.shared_tenancy ? 0 : 1

  name_prefix = "${local.naming_prefix}-vpce-"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.naming_prefix}-vpce-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_from_api" {
  count = local.shared_tenancy ? 0 : 1

  security_group_id            = aws_security_group.vpc_endpoints[0].id
  description                  = "HTTPS from API security group"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.api.id
}

resource "aws_vpc_endpoint" "ses" {
  count = local.shared_tenancy ? 0 : 1

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.email"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${local.naming_prefix}-ses-endpoint"
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  count = local.shared_tenancy ? 0 : 1

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${local.naming_prefix}-secretsmanager-endpoint"
  }
}
