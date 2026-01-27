# ============================================================================
# EKS Add-ons 모듈 - 변수 정의
# ============================================================================

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS 클러스터 API 엔드포인트"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "EKS 클러스터 CA 인증서 (Base64)"
  type        = string
}

variable "cluster_oidc_provider_arn" {
  description = "OIDC Provider ARN (IRSA용)"
  type        = string
}

variable "cluster_oidc_provider_url" {
  description = "OIDC Provider URL (https:// 제외)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID (ALB Controller에서 사용)"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}
