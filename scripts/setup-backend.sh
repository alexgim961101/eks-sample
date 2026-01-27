#!/bin/bash
# ============================================================================
# Terraform Backend 초기 설정 스크립트
# ============================================================================
# 이 스크립트는 Terraform 상태(State)를 저장할 S3 버킷과
# 동시 수정을 방지하는 DynamoDB 테이블을 생성합니다.
#
# 💡 왜 필요한가?
# -----------------
# Terraform은 인프라의 "현재 상태"를 terraform.tfstate 파일에 저장합니다.
# 이 파일이 없으면 Terraform은 이전에 생성한 리소스를 알 수 없습니다.
#
# 문제점:
#   1. 로컬에만 저장하면 팀원과 공유가 어렵습니다.
#   2. 실수로 삭제하면 인프라 관리가 불가능해집니다.
#   3. 두 사람이 동시에 terraform apply를 실행하면 충돌이 발생합니다.
#
# 해결책:
#   - S3: 상태 파일을 중앙에서 안전하게 저장 (버전 관리 포함)
#   - DynamoDB: 한 번에 한 사람만 수정할 수 있도록 "잠금(Lock)" 기능 제공
# ============================================================================

set -e  # 에러 발생 시 스크립트 중단

# 색상 정의 (출력 가독성 향상)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정값
REGION="ap-northeast-2"
DYNAMODB_TABLE="eks-terraform-locks"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE} Terraform Backend 설정 시작${NC}"
echo -e "${BLUE}============================================${NC}"

# 1. AWS 계정 ID 조회
echo -e "\n${YELLOW}[1/5] AWS 계정 정보 확인 중...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ AWS 자격 증명이 설정되지 않았습니다.${NC}"
    echo "   'aws configure'를 먼저 실행하세요."
    exit 1
fi

echo -e "${GREEN}✅ AWS Account ID: ${ACCOUNT_ID}${NC}"

# 버킷 이름 생성 (계정 ID를 포함하여 고유하게)
BUCKET_NAME="eks-terraform-state-${ACCOUNT_ID}"

# 2. S3 버킷 생성
echo -e "\n${YELLOW}[2/5] S3 버킷 생성 중: ${BUCKET_NAME}${NC}"

# 버킷이 이미 존재하는지 확인
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo -e "${GREEN}✅ 버킷이 이미 존재합니다.${NC}"
else
    # ap-northeast-2는 LocationConstraint가 필요함
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"
    
    echo -e "${GREEN}✅ S3 버킷 생성 완료${NC}"
fi

# 3. S3 버킷 버전 관리 활성화
echo -e "\n${YELLOW}[3/5] S3 버킷 버전 관리 활성화 중...${NC}"
echo -e "${BLUE}   💡 버전 관리를 활성화하면 상태 파일의 이전 버전을 복구할 수 있습니다.${NC}"

aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

echo -e "${GREEN}✅ 버전 관리 활성화 완료${NC}"

# 4. S3 버킷 암호화 설정
echo -e "\n${YELLOW}[4/5] S3 버킷 서버측 암호화 설정 중...${NC}"
echo -e "${BLUE}   💡 상태 파일에는 민감한 정보가 포함될 수 있으므로 암호화가 필수입니다.${NC}"

aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'

echo -e "${GREEN}✅ 암호화 설정 완료${NC}"

# 5. DynamoDB 테이블 생성
echo -e "\n${YELLOW}[5/5] DynamoDB 테이블 생성 중: ${DYNAMODB_TABLE}${NC}"
echo -e "${BLUE}   💡 DynamoDB는 State Locking에 사용됩니다.${NC}"
echo -e "${BLUE}   💡 두 사람이 동시에 terraform apply를 실행하면 하나는 대기합니다.${NC}"

# 테이블이 이미 존재하는지 확인
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" 2>/dev/null; then
    echo -e "${GREEN}✅ DynamoDB 테이블이 이미 존재합니다.${NC}"
else
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$REGION"
    
    echo -e "${GREEN}✅ DynamoDB 테이블 생성 완료${NC}"
fi

# 완료 메시지
echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN} ✅ Backend 설정 완료!${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "\n다음 정보를 ${YELLOW}environments/dev/backend.tf${NC}에 입력하세요:\n"
echo -e "  ${BLUE}bucket${NC}         = \"${BUCKET_NAME}\""
echo -e "  ${BLUE}dynamodb_table${NC} = \"${DYNAMODB_TABLE}\""
echo -e "  ${BLUE}region${NC}         = \"${REGION}\""
echo ""
