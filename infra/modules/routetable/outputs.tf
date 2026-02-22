output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of IDs of the private route tables"
  value       = aws_route_table.private[*].id
}

output "secure_route_table_ids" {
  description = "List of IDs of the secure route tables (no internet access)"
  value       = aws_route_table.secure[*].id
}
