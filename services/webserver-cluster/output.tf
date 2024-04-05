output "lb_dns_name" {
  description = "public ip of lb_dns_name"
  value       = aws_lb.example.dns_name
}

output "alb_security_grp_id" {
  description = "id of alb security group to use for addition of rules if required"
  value = aws_security_group.alb.id
}
