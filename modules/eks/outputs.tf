# ============================================================================
# EKS 모듈 - 출력값 정의
# ============================================================================
# 다른 모듈에서 참조할 수 있는 값들을 노출합니다.

output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API 서버 엔드포인트 URL"
  value       = aws_eks_cluster.this.endpoint

  # 💡 이 URL로 kubectl이 클러스터에 연결합니다.
  # 예: https://XXXXXXXX.gr7.ap-northeast-2.eks.amazonaws.com
}

output "cluster_ca_certificate" {
  description = "클러스터 CA 인증서 (Base64 인코딩)"
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true

  # 💡 kubectl이 API 서버를 신뢰하기 위해 사용합니다.
}

output "cluster_security_group_id" {
  description = "EKS 클러스터 Security Group ID"
  value       = aws_security_group.cluster.id
}

output "cluster_version" {
  description = "EKS Kubernetes 버전"
  value       = aws_eks_cluster.this.version
}

output "oidc_provider_arn" {
  description = "OIDC Provider ARN (IRSA 설정에 필요)"
  value       = aws_iam_openid_connect_provider.cluster.arn

  # 💡 Add-on 모듈에서 IAM Role과 서비스 계정을 연결할 때 사용합니다.
}

output "oidc_provider_url" {
  description = "OIDC Provider URL (https:// 제외)"
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

output "node_role_arn" {
  description = "노드 그룹 IAM 역할 ARN"
  value       = aws_iam_role.node.arn
}

output "node_security_group_id" {
  description = "노드 그룹에 자동 생성된 Security Group ID"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# 💡 kubectl 설정 명령어 출력
output "configure_kubectl_command" {
  description = "kubectl 설정 명령어"
  value       = "aws eks update-kubeconfig --region ap-northeast-2 --name ${aws_eks_cluster.this.name}"
}
