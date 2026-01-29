#!/bin/bash
###############################################################################
# GitHub OIDC Provider 및 IAM Role 설정 스크립트
###############################################################################
# 이 스크립트는 GitHub Actions에서 AWS에 안전하게 접근할 수 있도록
# OIDC Provider와 IAM Role을 생성합니다.
#
# 💡 학습 포인트:
# - OIDC (OpenID Connect): 외부 ID 공급자를 통한 인증
# - GitHub Actions는 JWT 토큰을 발급하고, AWS가 이를 검증
# - 장기 Access Key 없이 안전하게 AWS 리소스에 접근 가능
#
# ⚠️ 사전 요구사항:
# - AWS CLI v2 설치 및 설정
# - 적절한 IAM 권한 (IAM Full Access)
###############################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

###############################################################################
# 설정 변수
###############################################################################
# 사용자 입력 또는 기본값 사용
GITHUB_ORG="${GITHUB_ORG:-}"
GITHUB_REPO="${GITHUB_REPO:-}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
ROLE_NAME="${ROLE_NAME:-github-actions-terraform-role}"

###############################################################################
# GitHub 저장소 정보 입력
###############################################################################
echo ""
echo "============================================================"
echo "  GitHub OIDC Provider 및 IAM Role 설정"
echo "============================================================"
echo ""

# GitHub Organization/Username 입력
if [[ -z "$GITHUB_ORG" ]]; then
    read -p "GitHub Organization 또는 Username을 입력하세요: " GITHUB_ORG
fi

# GitHub Repository 이름 입력
if [[ -z "$GITHUB_REPO" ]]; then
    read -p "GitHub Repository 이름을 입력하세요: " GITHUB_REPO
fi

echo ""
log_info "설정 정보:"
log_info "  - GitHub: ${GITHUB_ORG}/${GITHUB_REPO}"
log_info "  - AWS Region: ${AWS_REGION}"
log_info "  - IAM Role Name: ${ROLE_NAME}"
echo ""

###############################################################################
# AWS 계정 정보 확인
###############################################################################
log_info "AWS 계정 정보 확인 중..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
log_success "AWS Account ID: ${AWS_ACCOUNT_ID}"

###############################################################################
# Step 1: GitHub OIDC Provider 생성
###############################################################################
echo ""
log_info "Step 1: GitHub OIDC Provider 확인/생성..."

# OIDC Provider URL
OIDC_PROVIDER_URL="token.actions.githubusercontent.com"
OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_URL}"

# 기존 OIDC Provider 확인
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${OIDC_PROVIDER_ARN}" >/dev/null 2>&1; then
    log_warn "GitHub OIDC Provider가 이미 존재합니다. 건너뜁니다."
else
    log_info "GitHub OIDC Provider 생성 중..."
    
    # GitHub OIDC Provider의 thumbprint
    # 참고: https://github.blog/changelog/2023-06-27-github-actions-update-on-oidc-integration-with-aws/
    THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"
    
    aws iam create-open-id-connect-provider \
        --url "https://${OIDC_PROVIDER_URL}" \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list "${THUMBPRINT}"
    
    log_success "GitHub OIDC Provider 생성 완료!"
fi

###############################################################################
# Step 2: IAM Trust Policy 생성
###############################################################################
echo ""
log_info "Step 2: IAM Trust Policy 생성 중..."

# Trust Policy JSON
# 💡 학습 포인트:
# - sub 조건: 특정 Organization/Repository만 허용
# - main 브랜치와 environment:dev만 허용 (보안 강화)
TRUST_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "${OIDC_PROVIDER_ARN}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": [
                        "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main",
                        "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:dev",
                        "repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request"
                    ]
                }
            }
        }
    ]
}
EOF
)

echo "${TRUST_POLICY}" > /tmp/trust-policy.json
log_success "Trust Policy 생성 완료!"

###############################################################################
# Step 3: IAM Policy 생성 (Terraform에 필요한 권한)
###############################################################################
echo ""
log_info "Step 3: IAM Policy 생성 중..."

POLICY_NAME="${ROLE_NAME}-policy"
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

# Terraform에 필요한 권한
# ⚠️ 프로덕션에서는 더 제한된 권한 사용 권장
POLICY_DOCUMENT=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "S3BackendAccess",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetBucketVersioning"
            ],
            "Resource": [
                "arn:aws:s3:::*-terraform-state-*",
                "arn:aws:s3:::*-terraform-state-*/*",
                "arn:aws:s3:::*-terraform-state",
                "arn:aws:s3:::*-terraform-state/*"
            ]
        },
        {
            "Sid": "DynamoDBLockAccess",
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:DeleteItem",
                "dynamodb:DescribeTable"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/*-terraform-locks"
        },
        {
            "Sid": "VPCAccess",
            "Effect": "Allow",
            "Action": [
                "ec2:*Vpc*",
                "ec2:*Subnet*",
                "ec2:*Route*",
                "ec2:*RouteTable*",
                "ec2:*InternetGateway*",
                "ec2:*NatGateway*",
                "ec2:*ElasticIp*",
                "ec2:*Address*",
                "ec2:*SecurityGroup*",
                "ec2:*NetworkAcl*",
                "ec2:*Tags*",
                "ec2:Describe*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "EKSAccess",
            "Effect": "Allow",
            "Action": [
                "eks:*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "IAMAccess",
            "Effect": "Allow",
            "Action": [
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:GetRole",
                "iam:PassRole",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy",
                "iam:PutRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:GetRolePolicy",
                "iam:CreatePolicy",
                "iam:DeletePolicy",
                "iam:GetPolicy",
                "iam:GetPolicyVersion",
                "iam:ListPolicyVersions",
                "iam:CreatePolicyVersion",
                "iam:DeletePolicyVersion",
                "iam:ListRolePolicies",
                "iam:ListAttachedRolePolicies",
                "iam:TagRole",
                "iam:UntagRole",
                "iam:TagPolicy",
                "iam:UntagPolicy",
                "iam:ListInstanceProfilesForRole",
                "iam:CreateOpenIDConnectProvider",
                "iam:GetOpenIDConnectProvider",
                "iam:DeleteOpenIDConnectProvider",
                "iam:TagOpenIDConnectProvider"
            ],
            "Resource": "*"
        },
        {
            "Sid": "AutoScalingAccess",
            "Effect": "Allow",
            "Action": [
                "autoscaling:*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ELBAccess",
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "CloudWatchLogsAccess",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:DeleteLogGroup",
                "logs:DescribeLogGroups",
                "logs:TagLogGroup",
                "logs:PutRetentionPolicy"
            ],
            "Resource": "*"
        },
        {
            "Sid": "STSAccess",
            "Effect": "Allow",
            "Action": [
                "sts:GetCallerIdentity"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)

echo "${POLICY_DOCUMENT}" > /tmp/policy-document.json

# 기존 Policy 확인 및 생성
if aws iam get-policy --policy-arn "${POLICY_ARN}" >/dev/null 2>&1; then
    log_warn "Policy가 이미 존재합니다. 새 버전을 생성합니다..."
    
    # 기존 버전 삭제 (최대 5개 제한)
    VERSIONS=$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" --query 'Versions[?!IsDefaultVersion].VersionId' --output text)
    for VERSION in $VERSIONS; do
        aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id "${VERSION}" 2>/dev/null || true
    done
    
    # 새 버전 생성
    aws iam create-policy-version \
        --policy-arn "${POLICY_ARN}" \
        --policy-document file:///tmp/policy-document.json \
        --set-as-default
else
    aws iam create-policy \
        --policy-name "${POLICY_NAME}" \
        --policy-document file:///tmp/policy-document.json
fi

log_success "IAM Policy 생성/업데이트 완료!"

###############################################################################
# Step 4: IAM Role 생성
###############################################################################
echo ""
log_info "Step 4: IAM Role 생성 중..."

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
    log_warn "Role이 이미 존재합니다. Trust Policy를 업데이트합니다..."
    aws iam update-assume-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-document file:///tmp/trust-policy.json
else
    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --description "Role for GitHub Actions to run Terraform"
fi

# Policy 연결
aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn "${POLICY_ARN}" 2>/dev/null || true

log_success "IAM Role 생성/업데이트 완료!"

###############################################################################
# 정리 및 결과 출력
###############################################################################
rm -f /tmp/trust-policy.json /tmp/policy-document.json

echo ""
echo "============================================================"
log_success "GitHub OIDC 설정 완료!"
echo "============================================================"
echo ""
echo "다음 단계:"
echo ""
echo "1. GitHub Repository Settings > Secrets and variables > Actions"
echo "   에서 다음 Secret을 추가하세요:"
echo ""
echo -e "   ${YELLOW}AWS_ROLE_ARN${NC}: ${GREEN}${ROLE_ARN}${NC}"
echo ""
echo "2. GitHub Repository Settings > Environments 에서"
echo "   'dev' 환경을 생성하세요 (선택사항, 수동 승인용)"
echo ""
echo "3. GitHub Actions 워크플로우를 실행하세요!"
echo ""
echo "============================================================"
