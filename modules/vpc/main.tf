# ============================================================================
# VPC 모듈 - 메인 리소스 정의
# ============================================================================
#
# 💡 이 모듈이 생성하는 리소스들:
# --------------------------------
# 1. VPC (Virtual Private Cloud)
# 2. Internet Gateway (인터넷 연결)
# 3. Public Subnets (2개 AZ)
# 4. Private Subnets (2개 AZ)
# 5. NAT Gateway (Private → 인터넷 아웃바운드)
# 6. Route Tables (라우팅 규칙)
#
# 💡 아키텍처 다이어그램:
# ----------------------
#
#                     ┌─────────────────────────────────────────────────────┐
#                     │                       VPC                           │
#                     │                   10.0.0.0/16                       │
#     ┌───────────────┼───────────────────────────────────────────────────┐  │
#     │               │           Availability Zone A                     │  │
#     │  ┌────────────┴─────────────┐    ┌──────────────────────────────┐ │  │
#     │  │    Public Subnet         │    │      Private Subnet          │ │  │
#     │  │    10.0.0.0/20           │    │      10.0.32.0/20            │ │  │
#     │  │  ┌─────────────────┐     │    │   ┌─────────────────┐        │ │  │
#     │  │  │   NAT Gateway   │     │    │   │   EKS Nodes     │        │ │  │
#     │  │  └────────┬────────┘     │    │   └────────┬────────┘        │ │  │
#     │  └───────────┼──────────────┘    └────────────┼─────────────────┘ │  │
#     │              │                                │                    │  │
#     └──────────────┼────────────────────────────────┼────────────────────┘  │
#                    │                                │                       │
#                    │    ┌───────────────────────────┘                       │
#                    │    │  (NAT를 통해 아웃바운드)                           │
#                    ▼    ▼                                                   │
#              ┌─────────────────┐                                            │
#              │ Internet Gateway│                                            │
#              └────────┬────────┘                                            │
#                       │                                                     │
#                       ▼                                                     │
#                   인터넷                                                     │
#                     └─────────────────────────────────────────────────────┘
#
# ============================================================================

# ----------------------------------------------------------------------------
# 데이터 소스: 사용 가능한 가용 영역 조회
# ----------------------------------------------------------------------------
# 💡 data 블록이란?
# AWS에서 이미 존재하는 정보를 조회할 때 사용합니다.
# resource는 "생성", data는 "조회"입니다.

data "aws_availability_zones" "available" {
  state = "available"

  # 특정 타입의 AZ 제외 (Local Zone 등)
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# ----------------------------------------------------------------------------
# 로컬 변수: 계산된 값들
# ----------------------------------------------------------------------------
# 💡 locals란?
# 반복적으로 사용되는 값이나 계산된 값을 저장합니다.
# 코드 가독성을 높이고 중복을 줄입니다.

locals {
  # 비용 절감을 위해 2개 AZ만 사용 (프로덕션에서는 3개 권장)
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
  len = length(local.azs)

  # 💡 cidrsubnet 함수 설명:
  # cidrsubnet(prefix, newbits, netnum)
  # - prefix: 기본 CIDR (예: 10.0.0.0/16)
  # - newbits: 추가할 비트 수 (16 + 4 = /20)
  # - netnum: 서브넷 번호 (0, 1, 2, ...)
  #
  # 예시: cidrsubnet("10.0.0.0/16", 4, 0) = "10.0.0.0/20"
  #       cidrsubnet("10.0.0.0/16", 4, 1) = "10.0.16.0/20"
  #       cidrsubnet("10.0.0.0/16", 4, 2) = "10.0.32.0/20"

  public_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i + local.len)]

  # 공통 태그
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# ============================================================================
# VPC 생성
# ============================================================================
# 💡 VPC란?
# 가상 프라이빗 클라우드 - AWS 내에서 논리적으로 격리된 네트워크입니다.
# 마치 회사 전용 데이터센터를 클라우드에 만드는 것과 같습니다.

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # DNS 관련 설정 (EKS에서 필수!)
  enable_dns_hostnames = true # EC2 인스턴스에 DNS 호스트 이름 할당
  enable_dns_support   = true # VPC 내 DNS 해석 지원

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
  })
}

# ============================================================================
# Internet Gateway
# ============================================================================
# 💡 Internet Gateway란?
# VPC를 인터넷에 연결하는 관문입니다.
# 이것이 없으면 VPC 내부에서 인터넷에 접근할 수 없습니다.

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-igw"
  })
}

# ============================================================================
# Public Subnets
# ============================================================================
# 💡 Public Subnet이란?
# 인터넷에서 직접 접근 가능한 서브넷입니다.
# - Internet Gateway로 직접 라우팅됨
# - 퍼블릭 IP가 할당될 수 있음
# - 용도: Load Balancer, Bastion Host, NAT Gateway

resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.public_subnets[count.index]
  availability_zone = local.azs[count.index]

  # 이 서브넷에 생성되는 인스턴스에 자동으로 퍼블릭 IP 할당
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-${local.azs[count.index]}"

    # 💡 EKS/ALB 관련 특수 태그
    # AWS Load Balancer Controller가 서브넷을 자동으로 찾기 위해 필요합니다.
    "kubernetes.io/role/elb"                                       = "1"
    "kubernetes.io/cluster/${var.project_name}-${var.environment}" = "shared"
  })
}

# ============================================================================
# Private Subnets
# ============================================================================
# 💡 Private Subnet이란?
# 인터넷에서 직접 접근할 수 없는 서브넷입니다.
# - NAT Gateway를 통해서만 아웃바운드 인터넷 접근 가능
# - 인바운드 직접 접근 불가 (보안 강화)
# - 용도: EKS 노드, 데이터베이스, 내부 서비스

resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnets[count.index]
  availability_zone = local.azs[count.index]

  # Private 서브넷은 퍼블릭 IP를 할당하지 않음
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-private-${local.azs[count.index]}"

    # Internal ALB용 태그
    "kubernetes.io/role/internal-elb"                              = "1"
    "kubernetes.io/cluster/${var.project_name}-${var.environment}" = "shared"
  })
}

# ============================================================================
# Elastic IP for NAT Gateway
# ============================================================================
# 💡 Elastic IP란?
# 고정된 퍼블릭 IP 주소입니다.
# NAT Gateway에 할당하여 Private 서브넷의 아웃바운드 IP를 고정합니다.

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-eip"
  })

  # Internet Gateway가 먼저 생성되어야 함
  depends_on = [aws_internet_gateway.this]
}

# ============================================================================
# NAT Gateway
# ============================================================================
# 💡 NAT Gateway란?
# Private 서브넷의 리소스가 인터넷에 접근할 수 있게 해주는 서비스입니다.
# 
# 작동 방식:
# 1. Private 서브넷의 EC2 → NAT Gateway로 트래픽 전송
# 2. NAT Gateway가 소스 IP를 자신의 Elastic IP로 변환
# 3. Internet Gateway를 통해 인터넷으로 전송
# 4. 응답은 역순으로 전달
#
# ⚠️ 비용 주의:
# - 시간당 $0.045 (약 $32/월)
# - 데이터 전송 비용 별도
# - 학습 환경에서는 1개만 생성 (프로덕션에서는 AZ당 1개 권장)

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # 첫 번째 Public 서브넷에 생성

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

# ============================================================================
# Route Tables
# ============================================================================
# 💡 Route Table이란?
# 네트워크 트래픽이 어디로 가야 하는지 규칙을 정의합니다.
# 마치 도로의 이정표와 같습니다.

# --- Public Route Table ---
# 모든 트래픽(0.0.0.0/0)을 Internet Gateway로 보냅니다.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"                  # 모든 목적지
    gateway_id = aws_internet_gateway.this.id # → Internet Gateway로
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-rt"
  })
}

# --- Private Route Table ---
# 모든 외부 트래픽을 NAT Gateway를 통해 보냅니다.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"             # 모든 목적지
    nat_gateway_id = aws_nat_gateway.this.id # → NAT Gateway를 통해
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-private-rt"
  })
}

# ============================================================================
# Route Table Associations
# ============================================================================
# 💡 Route Table Association이란?
# 서브넷을 Route Table에 연결합니다.
# 연결하지 않으면 VPC의 기본 Route Table이 적용됩니다.

# Public 서브넷들을 Public Route Table에 연결
resource "aws_route_table_association" "public" {
  count = length(local.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private 서브넷들을 Private Route Table에 연결
resource "aws_route_table_association" "private" {
  count = length(local.azs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
