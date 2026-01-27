# ============================================================================
# EKS 모듈 - 메인 리소스 정의
# ============================================================================
#
# 💡 EKS 아키텍처 개요:
# ---------------------
#
#     ┌─────────────────────────────────────────────────────────────────┐
#     │                        AWS Cloud                                │
#     │  ┌───────────────────────────────────────────────────────────┐  │
#     │  │                 EKS Control Plane                         │  │
#     │  │              (AWS가 완전 관리)                             │  │
#     │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐          │  │
#     │  │  │ API Server  │ │    etcd     │ │ Scheduler   │          │  │
#     │  │  └─────────────┘ └─────────────┘ └─────────────┘          │  │
#     │  └───────────────────────────┬───────────────────────────────┘  │
#     │                              │                                  │
#     │                              │ (Private Link)                   │
#     │                              │                                  │
#     │  ┌───────────────────────────▼───────────────────────────────┐  │
#     │  │                      VPC                                  │  │
#     │  │  ┌─────────────────────┐  ┌─────────────────────┐        │  │
#     │  │  │  Private Subnet A   │  │  Private Subnet B   │        │  │
#     │  │  │  ┌───────────────┐  │  │  ┌───────────────┐  │        │  │
#     │  │  │  │  EKS Node 1   │  │  │  │  EKS Node 2   │  │        │  │
#     │  │  │  │  (EC2)        │  │  │  │  (EC2)        │  │        │  │
#     │  │  │  └───────────────┘  │  │  └───────────────┘  │        │  │
#     │  │  └─────────────────────┘  └─────────────────────┘        │  │
#     │  └───────────────────────────────────────────────────────────┘  │
#     └─────────────────────────────────────────────────────────────────┘
#
# 💡 주요 개념:
# - Control Plane: Kubernetes 마스터 (AWS 관리, 비용 $0.10/시간)
# - Node Group: 워커 노드들의 집합 (EC2 비용 발생)
# - OIDC Provider: IAM과 K8s 서비스 계정 연결 (IRSA)
#
# ============================================================================

# ============================================================================
# EKS Cluster IAM Role
# ============================================================================
# 💡 EKS 클러스터가 AWS 서비스를 호출하기 위한 IAM 역할입니다.
# 예: CloudWatch 로그 전송, EC2 Auto Scaling 그룹 관리 등

resource "aws_iam_role" "cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  # 💡 assume_role_policy란?
  # "누가 이 역할을 맡을 수 있는가?"를 정의합니다.
  # 여기서는 EKS 서비스(eks.amazonaws.com)만 이 역할을 맡을 수 있습니다.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-cluster-role"
    Environment = var.environment
  }
}

# 💡 AWS 관리형 정책 연결
# AmazonEKSClusterPolicy: EKS 클러스터 운영에 필요한 기본 권한
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# ============================================================================
# EKS Cluster Security Group
# ============================================================================
# 💡 Security Group이란?
# AWS의 가상 방화벽입니다. 인바운드/아웃바운드 트래픽을 제어합니다.

resource "aws_security_group" "cluster" {
  name        = "${var.project_name}-${var.environment}-eks-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  # 💡 Egress (아웃바운드) 규칙
  # 클러스터 → 외부로 나가는 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # -1 = 모든 프로토콜
    cidr_blocks = ["0.0.0.0/0"] # 모든 목적지
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-cluster-sg"
    Environment = var.environment
  }
}

# ============================================================================
# EKS Cluster
# ============================================================================
# 💡 이것이 EKS의 핵심 리소스입니다!
# Control Plane(마스터)을 생성합니다. AWS가 완전 관리하며, 비용은 $0.10/시간입니다.

resource "aws_eks_cluster" "this" {
  name     = "${var.project_name}-${var.environment}"
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  # 💡 vpc_config: 클러스터의 네트워크 설정
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.cluster.id]

    # 💡 endpoint 설정:
    # - endpoint_private_access: VPC 내부에서 API 서버 접근 허용
    # - endpoint_public_access: 인터넷에서 API 서버 접근 허용
    endpoint_private_access = true
    endpoint_public_access  = true # 학습용: 로컬 PC에서 kubectl 사용 가능
  }

  # 💡 클러스터 로그 활성화
  # CloudWatch Logs로 전송됩니다. 트러블슈팅에 유용합니다.
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # IAM 역할 정책이 먼저 연결되어야 함
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]

  tags = {
    Name        = "${var.project_name}-${var.environment}"
    Environment = var.environment
  }
}

# ============================================================================
# OIDC Provider for IRSA (IAM Roles for Service Accounts)
# ============================================================================
# 💡 IRSA란?
# Kubernetes의 Service Account와 AWS IAM Role을 연결하는 기능입니다.
#
# 왜 필요한가?
# - Pod가 AWS 서비스(S3, DynamoDB 등)에 접근해야 할 때
# - Node의 IAM 역할을 공유하는 대신, Pod별로 최소 권한 부여 가능
#
# 예시:
# [Pod A: S3 읽기 전용] ←→ [IAM Role: S3ReadOnly]
# [Pod B: DynamoDB 쓰기] ←→ [IAM Role: DynamoDBWrite]

# OIDC Provider의 인증서 정보 조회
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# OIDC Provider 생성
resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-oidc"
    Environment = var.environment
  }
}

# ============================================================================
# Node Group IAM Role
# ============================================================================
# 💡 EKS 노드(EC2)가 AWS 서비스를 호출하기 위한 IAM 역할입니다.
# 예: ECR에서 이미지 Pull, CloudWatch로 메트릭 전송 등

resource "aws_iam_role" "node" {
  name = "${var.project_name}-${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com" # EC2 서비스가 이 역할을 맡음
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-node-role"
    Environment = var.environment
  }
}

# 💡 노드에 필요한 AWS 관리형 정책들
# 각 정책은 특정 기능을 위한 권한을 제공합니다.

# 1. EKS 워커 노드 기본 정책
# - Control Plane과 통신, 노드 등록 등
resource "aws_iam_role_policy_attachment" "node_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

# 2. VPC CNI 플러그인 정책
# - Pod에 VPC IP 주소 할당
# - 네트워크 인터페이스 관리
resource "aws_iam_role_policy_attachment" "node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

# 3. ECR 읽기 전용 정책
# - Amazon ECR에서 컨테이너 이미지 Pull
resource "aws_iam_role_policy_attachment" "node_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

# ============================================================================
# Managed Node Group
# ============================================================================
# 💡 Managed Node Group이란?
# AWS가 관리하는 EC2 인스턴스 그룹입니다.
# - 노드 프로비저닝, 업데이트, 종료를 AWS가 처리
# - Auto Scaling Group을 자동으로 생성/관리
#
# 대안: Self-managed Node Group (직접 EC2 관리)
#      Fargate (서버리스, 노드 없음)

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project_name}-${var.environment}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  # 💡 인스턴스 타입 설정
  instance_types = var.node_instance_types

  # 💡 용량 타입
  # ON_DEMAND: 안정적이지만 비용 높음
  # SPOT: 최대 90% 저렴하지만 중단 가능성
  capacity_type = "ON_DEMAND"

  # 💡 스케일링 설정
  scaling_config {
    desired_size = var.node_desired_size # 원하는 노드 수
    min_size     = var.node_min_size     # 최소 노드 수
    max_size     = var.node_max_size     # 최대 노드 수 (Autoscaling 상한)
  }

  # 💡 업데이트 설정
  # 노드 업데이트 시 동시에 사용 불가능한 최대 노드 수
  update_config {
    max_unavailable = 1
  }

  # 💡 노드에 Kubernetes 레이블 추가
  # Pod 스케줄링 시 nodeSelector로 사용 가능
  labels = {
    Environment = var.environment
    NodeGroup   = "default"
  }

  # IAM 정책이 먼저 연결되어야 함
  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  tags = {
    Name        = "${var.project_name}-${var.environment}-ng"
    Environment = var.environment
  }

  # 💡 노드 그룹 업데이트 시 기존 노드를 유지하면서 새 노드 생성
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# test commit
