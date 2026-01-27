# ============================================================================
# Dev 환경 출력값 정의
# ============================================================================
# 💡 terraform apply 후 콘솔에 출력되는 값들입니다.
# 클러스터 접속 정보 등 유용한 값을 노출합니다.
# ============================================================================

# ============================================================================
# VPC 정보
# ============================================================================
output "vpc_id" {
  description = "생성된 VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private 서브넷 ID 목록"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public 서브넷 ID 목록"
  value       = module.vpc.public_subnet_ids
}

# ============================================================================
# EKS 클러스터 정보
# ============================================================================
output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API 서버 엔드포인트"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "EKS Kubernetes 버전"
  value       = module.eks.cluster_version
}

# ============================================================================
# kubectl 설정 명령어
# ============================================================================
output "configure_kubectl" {
  description = "kubectl 설정 명령어 (복사해서 실행하세요!)"
  value       = module.eks.configure_kubectl_command
}

# ============================================================================
# Add-ons 정보
# ============================================================================
output "addons_installed" {
  description = "설치된 Add-ons 목록"
  value       = module.eks_addons.addons_installed
}
