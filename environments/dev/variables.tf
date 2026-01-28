# ============================================================================
# Dev 환경 변수 정의
# ============================================================================
# 💡 이 파일은 dev 환경의 설정값을 정의합니다.
# 다른 환경(staging, prod)을 만들 때는 이 파일을 복사하고 값을 변경합니다.
# ============================================================================

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "환경 이름"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "프로젝트 이름 (리소스 네이밍에 사용)"
  type        = string
  default     = "eks-study"
}

# ============================================================================
# VPC 설정
# ============================================================================
variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

# ============================================================================
# EKS 클러스터 설정
# ============================================================================
variable "cluster_version" {
  description = "EKS Kubernetes 버전"
  type        = string
  default     = "1.34"
}

# ============================================================================
# 노드 그룹 설정
# ============================================================================
variable "node_instance_types" {
  description = "노드 인스턴스 타입"
  type        = list(string)
  default     = ["t3.small"] # 💡 학습용 최소 사양
}

variable "node_desired_size" {
  description = "원하는 노드 수"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "최소 노드 수"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "최대 노드 수"
  type        = number
  default     = 3
}
