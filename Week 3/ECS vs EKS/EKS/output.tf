# ==========================================
# 1. EKS CLUSTER OUTPUTS
# ==========================================
output "cluster_name" {
  description = "The name of the EKS cluster for updating kubeconfig."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "The endpoint for the Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster."
  value       = module.eks.cluster_certificate_authority_data
}

# ==========================================
# 2. DATABASE OUTPUTS
# ==========================================
output "db_instance_endpoint" {
  description = "The connection endpoint for the RDS instance to be used by the backend."
  value       = aws_db_instance.postgres.address
}

output "db_instance_port" {
  description = "The port the database is listening on."
  value       = aws_db_instance.postgres.port
}

# ==========================================
# 3. IDENTITY & ACCESS (IRSA)
# ==========================================
output "backend_iam_role_arn" {
  description = "The ARN of the IAM role for the backend service account to use in Kubernetes manifests."
  value       = module.backend_irsa_role.iam_role_arn
}

# ==========================================
# 4. EDGE & SECURITY
# ==========================================
output "acm_certificate_arn" {
  description = "The ARN of the validated ACM certificate for Ingress SSL termination."
  value       = aws_acm_certificate.cert.arn
}