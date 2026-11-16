# Offline plan tests: the AWS provider is mocked, so no credentials or cloud resources are needed.
mock_provider "aws" {
  override_data {
    target = data.aws_availability_zones.available
    values = { names = ["eu-central-1a", "eu-central-1b", "eu-central-1c"] }
  }
  override_data {
    target = data.aws_ami.ubuntu
    values = { id = "ami-0123456789abcdef0" }
  }
  override_data {
    target = data.aws_iam_policy_document.ec2_assume
    values = { json = "{}" }
  }
  override_data {
    target = data.aws_iam_policy_document.flow_logs_assume
    values = { json = "{}" }
  }
  override_data {
    target = data.aws_iam_policy_document.flow_logs
    values = { json = "{}" }
  }
}

variables {
  vpn_allowed_cidrs = ["203.0.113.10/32"]
}

run "three_az_layout" {
  command = plan

  assert {
    condition     = length(distinct([for s in aws_subnet.data : s.availability_zone])) == 3
    error_message = "MongoDB members must be spread over three availability zones."
  }
  assert {
    condition     = length(aws_instance.db) == 3
    error_message = "Expected a three-member replica set."
  }
  assert {
    condition     = aws_autoscaling_group.web.min_size == 2 && aws_autoscaling_group.web.max_size == 2
    error_message = "Web tier should be fixed at two instances."
  }
  assert {
    condition     = aws_autoscaling_group.app.min_size == 2 && aws_autoscaling_group.app.max_size == 3
    error_message = "App tier should scale between two and three instances."
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "single_nat_gateway=true should create one NAT gateway."
  }
}

run "security_baseline" {
  command = plan

  assert {
    condition     = alltrue([for i in aws_instance.db : i.metadata_options[0].http_tokens == "required"])
    error_message = "IMDSv2 must be enforced on database instances."
  }
  assert {
    condition     = aws_launch_template.web.metadata_options[0].http_tokens == "required" && aws_launch_template.app.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be enforced in launch templates."
  }
  assert {
    condition     = alltrue([for i in aws_instance.db : i.root_block_device[0].encrypted])
    error_message = "Database volumes must be encrypted."
  }
  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.db : r.cidr_ipv4 == null])
    error_message = "MongoDB must only be reachable from security groups, never from CIDR ranges."
  }
  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.vpn : r.cidr_ipv4 != "0.0.0.0/0"])
    error_message = "The VPN endpoint must not be open to the whole internet."
  }
  assert {
    condition     = alltrue([for s in concat(aws_subnet.app, aws_subnet.data) : s.map_public_ip_on_launch == false])
    error_message = "App and data subnets must not assign public IPs."
  }
}

run "https_when_certificate_given" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:eu-central-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1
    error_message = "An HTTPS listener should be created when a certificate is supplied."
  }
  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "redirect"
    error_message = "HTTP should redirect to HTTPS when a certificate is supplied."
  }
}

run "multi_az_nat" {
  command = plan

  variables {
    single_nat_gateway = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "single_nat_gateway=false should create one NAT gateway per AZ."
  }
}

run "rejects_empty_vpn_allowlist" {
  command = plan

  variables {
    vpn_allowed_cidrs = []
  }

  expect_failures = [var.vpn_allowed_cidrs]
}
