# ============================================================================
# EKS Add-ons 모듈 - 출력값 정의
# ============================================================================

output "lbc_role_arn" {
  description = "AWS Load Balancer Controller IAM Role ARN"
  value       = aws_iam_role.lbc.arn
}

output "ebs_csi_role_arn" {
  description = "EBS CSI Driver IAM Role ARN"
  value       = aws_iam_role.ebs_csi.arn
}

output "cluster_autoscaler_role_arn" {
  description = "Cluster Autoscaler IAM Role ARN"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "addons_installed" {
  description = "설치된 Add-ons 목록"
  value = [
    "aws-load-balancer-controller",
    "metrics-server",
    "aws-ebs-csi-driver",
    "cluster-autoscaler"
  ]
}
