# ============================================================================
# VPC 모듈 - 출력값 정의
# ============================================================================
# 💡 output이란?
# 모듈이 생성한 리소스의 정보를 외부에 노출합니다.
# 다른 모듈에서 이 값들을 참조할 수 있습니다.
#
# 예시:
#   module "eks" {
#     vpc_id = module.vpc.vpc_id  ← VPC 모듈의 output 참조
#   }
# ============================================================================

output "vpc_id" {
  description = "생성된 VPC의 ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC의 CIDR 블록"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public 서브넷 ID 목록"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private 서브넷 ID 목록 (EKS 노드가 배치될 위치)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "Public 서브넷 CIDR 블록 목록"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "Private 서브넷 CIDR 블록 목록"
  value       = aws_subnet.private[*].cidr_block
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.this.id
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway의 퍼블릭 IP (Private 서브넷의 아웃바운드 IP)"
  value       = aws_eip.nat.public_ip
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.this.id
}

output "availability_zones" {
  description = "사용된 가용 영역 목록"
  value       = local.azs
}
