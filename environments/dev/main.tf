# ============================================================================
# Dev 환경 메인 파일 - 모듈 호출
# ============================================================================
# 💡 이 파일에서 각 모듈을 호출하여 인프라를 구성합니다.
# 모듈은 레고 블록처럼 조립됩니다:
#   VPC → EKS → Add-ons
# ============================================================================

# ============================================================================
# VPC 모듈 호출
# ============================================================================
# 💡 VPC, 서브넷, NAT Gateway, Route Table 등을 생성합니다.
module "vpc" {
  source = "../../modules/vpc"

  environment  = var.environment
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
}

# ============================================================================
# EKS 모듈 호출
# ============================================================================
# 💡 EKS 클러스터, 노드 그룹, IAM 역할 등을 생성합니다.
# VPC 모듈의 출력값을 입력으로 사용합니다.
module "eks" {
  source = "../../modules/eks"

  environment     = var.environment
  project_name    = var.project_name
  cluster_version = var.cluster_version

  # VPC 모듈에서 출력된 값 사용
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # 노드 그룹 설정
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  # VPC가 먼저 생성되어야 함
  depends_on = [module.vpc]
}

# ============================================================================
# EKS Add-ons 모듈 호출
# ============================================================================
# 💡 AWS LB Controller, Metrics Server, EBS CSI Driver, Cluster Autoscaler
# EKS 클러스터의 OIDC Provider를 사용하여 IRSA를 설정합니다.
module "eks_addons" {
  source = "../../modules/eks-addons"

  cluster_name              = module.eks.cluster_name
  cluster_endpoint          = module.eks.cluster_endpoint
  cluster_ca_certificate    = module.eks.cluster_ca_certificate
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn
  cluster_oidc_provider_url = module.eks.oidc_provider_url
  vpc_id                    = module.vpc.vpc_id
  aws_region                = var.aws_region

  # EKS 클러스터가 먼저 생성되어야 함
  depends_on = [module.eks]
}
