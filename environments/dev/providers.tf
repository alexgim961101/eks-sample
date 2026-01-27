# ============================================================================
# Terraform Providers 설정
# ============================================================================
# 💡 Provider란?
# Terraform이 외부 서비스(AWS, K8s 등)와 통신하기 위한 플러그인입니다.
# 여기서 사용할 Provider들의 버전과 설정을 정의합니다.
# ============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # AWS Provider: VPC, EKS, IAM 등 AWS 리소스 관리
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Kubernetes Provider: K8s 리소스 관리 (ConfigMap 등)
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }

    # Helm Provider: Helm 차트로 K8s 애플리케이션 설치
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }

    # TLS Provider: 인증서 정보 조회 (OIDC thumbprint용)
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # HTTP Provider: 외부 URL에서 데이터 가져오기 (IAM 정책 등)
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# ============================================================================
# AWS Provider 설정
# ============================================================================
provider "aws" {
  region = var.aws_region

  # 💡 모든 리소스에 기본 태그 추가
  # 비용 추적, 리소스 관리에 유용합니다.
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  }
}

# ============================================================================
# Kubernetes Provider 설정
# ============================================================================
# 💡 EKS 클러스터 생성 후에만 사용 가능합니다.
# exec 블록을 사용해 AWS CLI로 인증 토큰을 얻습니다.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# ============================================================================
# Helm Provider 설정
# ============================================================================
# 💡 Helm 차트를 EKS 클러스터에 설치할 때 사용합니다.
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}
