# ============================================================================
# EKS 모듈 - 변수 정의
# ============================================================================

variable "environment" {
  description = "환경 이름 (dev, staging, prod)"
  type        = string
}

variable "project_name" {
  description = "프로젝트 이름"
  type        = string
}

variable "cluster_version" {
  description = "EKS Kubernetes 버전"
  type        = string
  default     = "1.28"

  # 💡 EKS 버전 정책:
  # - AWS는 최신 4개 버전만 지원
  # - 버전 EOL 전에 업그레이드 필요
  # - 마이너 버전만 지정 (1.28), 패치는 AWS 관리
}

variable "vpc_id" {
  description = "EKS 클러스터가 배치될 VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "EKS 노드가 배치될 Private 서브넷 ID 목록"
  type        = list(string)

  # 💡 왜 Private 서브넷인가?
  # - 노드를 인터넷에서 직접 접근 불가하게 (보안)
  # - 필요한 아웃바운드만 NAT Gateway 통해 허용
}

variable "node_instance_types" {
  description = "노드 그룹에 사용할 EC2 인스턴스 타입"
  type        = list(string)
  default     = ["t3.small"]

  # 💡 인스턴스 타입별 특성:
  # t3.small:  2 vCPU,  2GB RAM  - 학습/개발용
  # t3.medium: 2 vCPU,  4GB RAM  - 소규모 워크로드
  # m5.large:  2 vCPU,  8GB RAM  - 프로덕션 시작점
}

variable "node_desired_size" {
  description = "노드 그룹의 원하는 노드 수"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "노드 그룹의 최소 노드 수"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "노드 그룹의 최대 노드 수 (Autoscaling 상한)"
  type        = number
  default     = 3
}
