data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

locals {
  # Hardened defaults shared by every instance: IMDSv2 only and encrypted gp3 root volume.
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
}

# ---------------------------------------------------------------- web tier (Nginx)
resource "aws_lb" "public" {
  name                       = substr("${local.name}-public", 0, 32)
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.public_alb.id]
  subnets                    = aws_subnet.public[*].id
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "web" {
  name_prefix = "web-"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  health_check {
    path    = "/nginx-health"
    matcher = "200"
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.certificate_arn == null ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.web.arn
    }
  }

  dynamic "default_action" {
    for_each = var.certificate_arn == null ? [] : [1]
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = var.certificate_arn == null ? 0 : 1
  load_balancer_arn = aws_lb.public.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_launch_template" "web" {
  name_prefix            = "${local.name}-web-"
  image_id               = data.aws_ami.ubuntu.id
  instance_type          = var.web_instance_type
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data              = base64encode(templatefile("${path.module}/templates/nginx.sh.tftpl", { upstream = aws_lb.internal.dns_name }))
  iam_instance_profile { arn = aws_iam_instance_profile.instance.arn }
  metadata_options {
    http_endpoint               = local.metadata_options.http_endpoint
    http_tokens                 = local.metadata_options.http_tokens
    http_put_response_hop_limit = local.metadata_options.http_put_response_hop_limit
  }
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 10
      volume_type = "gp3"
      encrypted   = true
    }
  }
  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name}-web", Tier = "web" }
  }
}

resource "aws_autoscaling_group" "web" {
  name_prefix               = "${local.name}-web-"
  min_size                  = var.web_capacity.min
  desired_capacity          = var.web_capacity.desired
  max_size                  = var.web_capacity.max
  vpc_zone_identifier       = aws_subnet.app[*].id
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180
  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }
  instance_refresh {
    strategy = "Rolling"
    preferences { min_healthy_percentage = 50 }
  }
}

# ---------------------------------------------------------------- app tier (Node.js)
resource "aws_lb" "internal" {
  name                       = substr("${local.name}-internal", 0, 32)
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.internal_alb.id]
  subnets                    = aws_subnet.app[*].id
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "app" {
  name_prefix = "app-"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  health_check {
    path    = "/health"
    matcher = "200"
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_lb_listener" "internal" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP" # traffic never leaves the VPC
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_launch_template" "app" {
  name_prefix            = "${local.name}-app-"
  image_id               = data.aws_ami.ubuntu.id
  instance_type          = var.app_instance_type
  vpc_security_group_ids = [aws_security_group.app.id]
  user_data = base64encode(templatefile("${path.module}/templates/app.sh.tftpl", {
    mongo_uri = "mongodb://${join(",", [for i in aws_instance.db : "${i.private_ip}:27017"])}/demo?replicaSet=rs0"
  }))
  iam_instance_profile { arn = aws_iam_instance_profile.instance.arn }
  metadata_options {
    http_endpoint               = local.metadata_options.http_endpoint
    http_tokens                 = local.metadata_options.http_tokens
    http_put_response_hop_limit = local.metadata_options.http_put_response_hop_limit
  }
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 10
      volume_type = "gp3"
      encrypted   = true
    }
  }
  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name}-app", Tier = "app" }
  }
}

resource "aws_autoscaling_group" "app" {
  name_prefix               = "${local.name}-app-"
  min_size                  = var.app_capacity.min
  desired_capacity          = var.app_capacity.desired
  max_size                  = var.app_capacity.max
  vpc_zone_identifier       = aws_subnet.app[*].id
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180
  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }
  instance_refresh {
    strategy = "Rolling"
    preferences { min_healthy_percentage = 50 }
  }
}

resource "aws_autoscaling_policy" "app_cpu" {
  name                   = "cpu-target-60"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60
  }
}

# ---------------------------------------------------------------- data tier (MongoDB replica set)
resource "aws_instance" "db" {
  count                  = 3
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.data[count.index].id
  vpc_security_group_ids = [aws_security_group.db.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  user_data              = file("${path.module}/templates/mongodb.sh")
  monitoring             = true
  metadata_options {
    http_endpoint               = local.metadata_options.http_endpoint
    http_tokens                 = local.metadata_options.http_tokens
    http_put_response_hop_limit = local.metadata_options.http_put_response_hop_limit
  }
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }
  tags = { Name = "${local.name}-db-${count.index}", Tier = "data", ReplicaSet = "rs0" }
}

# ---------------------------------------------------------------- VPN (WireGuard)
resource "aws_instance" "vpn" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.vpn_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.vpn.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  source_dest_check      = false # routes traffic between VPN clients and the VPC
  user_data = templatefile("${path.module}/templates/wireguard.sh.tftpl", {
    client_cidr = var.vpn_client_cidr
    vpc_cidr    = var.vpc_cidr
  })
  metadata_options {
    http_endpoint               = local.metadata_options.http_endpoint
    http_tokens                 = local.metadata_options.http_tokens
    http_put_response_hop_limit = local.metadata_options.http_put_response_hop_limit
  }
  root_block_device {
    volume_size = 10
    volume_type = "gp3"
    encrypted   = true
  }
  tags = { Name = "${local.name}-vpn", Tier = "vpn" }
}

resource "aws_eip" "vpn" {
  domain   = "vpc"
  instance = aws_instance.vpn.id
  tags     = { Name = "${local.name}-vpn" }
}
