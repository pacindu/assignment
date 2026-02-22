output "natgw_id" {
  description = "The ID of the NAT Gateway"
  value       = aws_nat_gateway.this.id
}

output "eip_public_ip" {
  description = "The public IP address of the Elastic IP associated with the NAT Gateway"
  value       = aws_eip.nat.public_ip
}
