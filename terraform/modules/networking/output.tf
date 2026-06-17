output "vpc_id" {
  value = aws_vpc.project_vpc.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "private_security_group_id" {
  value = aws_security_group.private_sg.id
}

output "vpc_cidr" {
  value = aws_vpc.project_vpc.cidr_block
}

output "private_route_table_ids" {
  value = aws_route_table.private[*].id 
}