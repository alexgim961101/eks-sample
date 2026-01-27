# Terraform EKS Infrastructure

Terraform을 사용하여 AWS EKS 클러스터를 프로비저닝하고, GitHub Actions CI/CD 파이프라인을 구축합니다.

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud                            │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                    VPC (10.0.0.0/16)                  │  │
│  │  ┌─────────────────┐      ┌─────────────────┐        │  │
│  │  │  Public Subnet  │      │  Public Subnet  │        │  │
│  │  │  + NAT Gateway  │      │                 │        │  │
│  │  └─────────────────┘      └─────────────────┘        │  │
│  │  ┌─────────────────┐      ┌─────────────────┐        │  │
│  │  │ Private Subnet  │      │ Private Subnet  │        │  │
│  │  │  + EKS Nodes    │      │  + EKS Nodes    │        │  │
│  │  └─────────────────┘      └─────────────────┘        │  │
│  └───────────────────────────────────────────────────────┘  │
│                              │                              │
│                    ┌─────────▼─────────┐                    │
│                    │   EKS Control     │                    │
│                    │     Plane         │                    │
│                    └───────────────────┘                    │
└─────────────────────────────────────────────────────────────┘
```

## 디렉토리 구조

```
.
├── environments/           # 환경별 설정
│   └── dev/
│       ├── backend.tf      # S3 Backend 설정
│       ├── providers.tf    # Provider 설정
│       ├── variables.tf    # 변수 정의
│       ├── main.tf         # 모듈 호출
│       └── outputs.tf      # 출력값
│
├── modules/                # 재사용 가능한 모듈
│   ├── vpc/               # VPC, 서브넷, NAT Gateway
│   ├── eks/               # EKS 클러스터, 노드 그룹
│   └── eks-addons/        # LB Controller, Autoscaler 등
│
├── scripts/               # 유틸리티 스크립트
│   └── setup-backend.sh   # S3/DynamoDB 초기 설정
│
└── .github/workflows/     # CI/CD 파이프라인
    └── terraform.yml
```

## 사전 요구사항

- AWS CLI >= 2.0
- Terraform >= 1.5.0
- kubectl >= 1.28

## 시작하기

### 1. AWS 자격 증명 설정

```bash
aws configure
aws sts get-caller-identity  # 확인
```

### 2. Backend 설정 (최초 1회)

```bash
chmod +x scripts/setup-backend.sh
./scripts/setup-backend.sh
```

출력된 버킷 이름을 `environments/dev/backend.tf`에 입력하세요.

### 3. Terraform 실행

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

### 4. kubectl 설정

```bash
aws eks update-kubeconfig --region ap-northeast-2 --name eks-study-dev
kubectl get nodes
```

## 비용 안내

| 리소스 | 예상 비용 |
|--------|----------|
| EKS Control Plane | $0.10/시간 (~$72/월) |
| t3.small x 2 노드 | ~$30/월 |
| NAT Gateway | ~$32/월 |
| **합계** | **~$134/월** |

⚠️ 학습 후 반드시 리소스 삭제:

```bash
cd environments/dev
terraform destroy
```

## 포함된 Add-ons

| Add-on | 역할 |
|--------|------|
| AWS Load Balancer Controller | Ingress → ALB 자동 생성 |
| Metrics Server | HPA용 메트릭 수집 |
| EBS CSI Driver | PVC → EBS 볼륨 |
| Cluster Autoscaler | 노드 자동 스케일링 |
