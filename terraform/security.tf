# Least-privilege security groups: each tier only accepts traffic from the tier in front of it.

resource "aws_security_group" "public_alb" {
  name_prefix = "${local.name}-public-alb-"
  description = "Internet-facing load balancer"
  vpc_id      = aws_vpc.this.id
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "public_alb" {
  for_each          = toset(var.certificate_arn == null ? ["80"] : ["80", "443"])
  security_group_id = aws_security_group.public_alb.id
  description       = "HTTP(S) from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
}

resource "aws_security_group" "web" {
  name_prefix = "${local.name}-web-"
  description = "Nginx tier"
  vpc_id      = aws_vpc.this.id
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  security_group_id            = aws_security_group.web.id
  description                  = "HTTP from public ALB"
  referenced_security_group_id = aws_security_group.public_alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_security_group" "internal_alb" {
  name_prefix = "${local.name}-internal-alb-"
  description = "Internal load balancer in front of the app tier"
  vpc_id      = aws_vpc.this.id
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "internal_alb_from_web" {
  security_group_id            = aws_security_group.internal_alb.id
  description                  = "HTTP from Nginx tier"
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_security_group" "app" {
  name_prefix = "${local.name}-app-"
  description = "Node.js tier"
  vpc_id      = aws_vpc.this.id
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_internal_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "App port from internal ALB"
  referenced_security_group_id = aws_security_group.internal_alb.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

resource "aws_security_group" "db" {
  name_prefix = "${local.name}-db-"
  description = "MongoDB replica set: reachable only from the app tier, VPN and its own members"
  vpc_id      = aws_vpc.this.id
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "db" {
  for_each = {
    app  = aws_security_group.app.id
    vpn  = aws_security_group.vpn.id
    self = aws_security_group.db.id
  }
  security_group_id            = aws_security_group.db.id
  description                  = "MongoDB from ${each.key}"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 27017
  to_port                      = 27017
}

resource "aws_security_group" "vpn" {
  name_prefix = "${local.name}-vpn-"
  description = "WireGuard VPN gateway"
  vpc_id      = aws_vpc.this.id
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "vpn" {
  for_each          = toset(var.vpn_allowed_cidrs)
  security_group_id = aws_security_group.vpn.id
  description       = "WireGuard from allowed client network"
  cidr_ipv4         = each.value
  ip_protocol       = "udp"
  from_port         = 51820
  to_port           = 51820
}

# Outbound: instances need package mirrors and the SSM endpoints (via NAT); ALBs reach their targets.
resource "aws_vpc_security_group_egress_rule" "all" {
  for_each = {
    public_alb   = aws_security_group.public_alb.id
    web          = aws_security_group.web.id
    internal_alb = aws_security_group.internal_alb.id
    app          = aws_security_group.app.id
    db           = aws_security_group.db.id
    vpn          = aws_security_group.vpn.id
  }
  security_group_id = each.value
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
