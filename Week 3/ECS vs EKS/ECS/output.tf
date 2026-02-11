# --- Ingress Tier ---
output "alb_dns_name" {
  description = "Public entry point. Map your 'app.astralbyte.net' CNAME to this value."
  value       = aws_lb.main.dns_name
}

# --- Application Tier ---
output "ecs_cluster_name" {
  description = "Name of the ECS Cluster for CLI monitoring commands."
  value       = aws_ecs_cluster.main.name
}

output "service_discovery_namespace" {
  description = "The Service Connect DNS Namespace"
  value       = aws_service_discovery_private_dns_namespace.internal.name
}

output "service_discovery_id" {
  value = aws_service_discovery_private_dns_namespace.internal.id
}
# --- Persistence Tier ---
output "rds_endpoint" {
  description = "Internal database connection string."
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "Database listening port."
  value       = aws_db_instance.postgres.port
}

# --- Networking Tier ---
output "vpc_id" {
  description = "The ID of the Three-Tier VPC."
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Subnet IDs where the Fargate containers are running."
  value       = module.vpc.private_subnets
}

# --- Governance Tier ---
output "secrets_manager_arn" {
  description = "The ARN of the DB password secret in Secrets Manager."
  value       = aws_secretsmanager_secret.db_password.arn
}