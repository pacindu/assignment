output "alb_arn" {
  description = "The ARN of the Application Load Balancer"
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "The ARN suffix of the ALB (used in CloudWatch metrics)"
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "The canonical hosted zone ID of the ALB (for Route53 alias records)"
  value       = aws_lb.this.zone_id
}

output "http_listener_arn" {
  description = "The ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "The ARN of the HTTPS listener"
  value       = aws_lb_listener.https.arn
}
