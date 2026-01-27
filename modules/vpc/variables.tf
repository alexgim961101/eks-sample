# ============================================================================
# VPC 모듈 - 변수 정의
# ============================================================================
# 이 파일은 VPC 모듈에서 사용하는 입력 변수들을 정의합니다.
#
# 💡 Terraform 변수란?
# ---------------------
# 모듈을 호출할 때 외부에서 값을 주입할 수 있게 해주는 파라미터입니다.
# 이를 통해 같은 모듈을 dev, staging, prod 환경에서 재사용할 수 있습니다.
#
# 예시:
#   module "vpc" {
#     source       = "../../modules/vpc"
#     environment  = "dev"        ← 이 값이 var.environment로 전달됨
#     vpc_cidr     = "10.0.0.0/16"
#   }
# ============================================================================

variable "environment" {
  description = "환경 이름 (dev, staging, prod)"
  type        = string

  # 유효성 검사: 허용된 값만 사용 가능
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment는 dev, staging, prod 중 하나여야 합니다."
  }
}

variable "project_name" {
  description = "프로젝트 이름 (리소스 태깅에 사용)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC의 CIDR 블록 (예: 10.0.0.0/16)"
  type        = string

  # 💡 CIDR이란?
  # VPC 내에서 사용할 IP 주소 범위입니다.
  # 10.0.0.0/16 = 10.0.0.0 ~ 10.0.255.255 (65,536개 IP)

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr는 유효한 CIDR 형식이어야 합니다. (예: 10.0.0.0/16)"
  }
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}
