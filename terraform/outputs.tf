output "url" {
  description = "Public entry point."
  value       = "${var.certificate_arn == null ? "http" : "https"}://${aws_lb.public.dns_name}"
}

output "vpn_endpoint" {
  description = "WireGuard endpoint for client configuration."
  value       = "${aws_eip.vpn.public_ip}:51820"
}

output "vpn_instance_id" {
  description = "Use with SSM to fetch the server public key and add peers."
  value       = aws_instance.vpn.id
}

output "db_instance_ids" {
  description = "MongoDB replica-set members (pass to scripts/init-replica-set.sh)."
  value       = aws_instance.db[*].id
}

output "db_private_ips" {
  value = aws_instance.db[*].private_ip
}
