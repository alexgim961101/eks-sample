# ============================================================================
# EKS Add-ons 모듈 - 메인 리소스 정의
# ============================================================================
#
# 💡 이 모듈이 설치하는 Add-ons:
# --------------------------------
# 1. AWS Load Balancer Controller - Ingress를 ALB/NLB로 자동 프로비저닝
# 2. Metrics Server              - HPA(수평 Pod 오토스케일링)에 필요
# 3. EBS CSI Driver              - EBS 볼륨을 PersistentVolume으로 사용
# 4. Cluster Autoscaler          - 노드 수 자동 조절
#
# 💡 왜 필요한가?
# ---------------
# EKS는 기본적으로 "빈 클러스터"입니다. 실무에서 필요한 기능들을
# Add-on으로 설치해야 합니다.
#
#   Kubernetes Ingress 생성 → ??? → 아무것도 안 됨!
#   + AWS LB Controller 설치 → ALB가 자동으로 생성됨!
#
# ============================================================================

# ============================================================================
# 1. AWS Load Balancer Controller
# ============================================================================
# 💡 역할:
# Kubernetes의 Ingress/Service 리소스를 AWS ALB/NLB로 자동 프로비저닝합니다.
#
# 예시:
#   apiVersion: networking.k8s.io/v1
#   kind: Ingress
#   metadata:
#     name: my-app
#     annotations:
#       kubernetes.io/ingress.class: alb
#   ...
#   → AWS ALB가 자동으로 생성됨!

# IAM 정책 (AWS 공식 정책 문서에서 가져옴)
data "http" "lbc_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.6.0/docs/install/iam_policy.json"

  # 💡 이 URL은 AWS Load Balancer Controller 공식 GitHub에서 제공하는
  #    IAM 정책 JSON입니다. EC2, ELB, ACM 등에 대한 권한이 포함되어 있습니다.
}

resource "aws_iam_policy" "lbc" {
  name        = "${var.cluster_name}-AWSLoadBalancerControllerIAMPolicy"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = data.http.lbc_iam_policy.response_body

  tags = {
    Name = "${var.cluster_name}-lbc-policy"
  }
}

# 💡 IRSA 설정: Service Account와 IAM Role 연결
# 앞서 배운 OIDC를 사용합니다!
resource "aws_iam_role" "lbc" {
  name = "${var.cluster_name}-aws-lbc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.cluster_oidc_provider_arn # ← OIDC Provider 신뢰!
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # 💡 이 조건이 핵심!
          # "kube-system 네임스페이스의 aws-load-balancer-controller 서비스 계정만
          #  이 역할을 사용할 수 있다"
          "${var.cluster_oidc_provider_url}:aud" = "sts.amazonaws.com"
          "${var.cluster_oidc_provider_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })

  tags = {
    Name = "${var.cluster_name}-lbc-role"
  }
}

resource "aws_iam_role_policy_attachment" "lbc" {
  policy_arn = aws_iam_policy.lbc.arn
  role       = aws_iam_role.lbc.name
}

# Helm으로 AWS Load Balancer Controller 설치
resource "helm_release" "aws_lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.6.2"

  # 💡 Helm values 설정
  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  # 💡 핵심! 서비스 계정에 IAM Role 연결 (IRSA)
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.lbc.arn
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  depends_on = [aws_iam_role_policy_attachment.lbc]
}

# ============================================================================
# 2. Metrics Server
# ============================================================================
# 💡 역할:
# Pod의 CPU/메모리 사용량을 수집합니다.
# HPA (Horizontal Pod Autoscaler)가 이 데이터를 사용해 Pod 수를 조절합니다.
#
# 예시:
#   kubectl top pods    ← Metrics Server가 없으면 안 됨!
#   kubectl top nodes
#
#   HPA 설정:
#   spec:
#     minReplicas: 1
#     maxReplicas: 10
#     metrics:
#       - type: Resource
#         resource:
#           name: cpu
#           target:
#             type: Utilization
#             averageUtilization: 50  ← CPU 50% 초과 시 Pod 추가

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.11.0"

  # 💡 EKS에서 필요한 설정
  # kubelet의 자체 서명 인증서를 허용 (학습 환경용)
  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }
}

# ============================================================================
# 3. EBS CSI Driver
# ============================================================================
# 💡 역할:
# Kubernetes PersistentVolume을 AWS EBS 볼륨으로 자동 프로비저닝합니다.
#
# 예시:
#   kind: PersistentVolumeClaim
#   spec:
#     storageClassName: gp3
#     resources:
#       requests:
#         storage: 10Gi
#   → AWS EBS gp3 볼륨 10GB가 자동 생성!

# IRSA 설정
resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.cluster_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.cluster_oidc_provider_url}:aud" = "sts.amazonaws.com"
          "${var.cluster_oidc_provider_url}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })

  tags = {
    Name = "${var.cluster_name}-ebs-csi-role"
  }
}

# AWS 관리형 정책 연결
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi.name
}

# 💡 EKS Add-on으로 설치 (Helm이 아닌 AWS 네이티브 방식)
# AWS가 직접 관리하므로 업데이트가 더 쉽습니다.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.25.0-eksbuild.1"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  # 충돌 시 덮어쓰기
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_iam_role_policy_attachment.ebs_csi]

  tags = {
    Name = "${var.cluster_name}-ebs-csi"
  }
}

# ============================================================================
# 4. Cluster Autoscaler
# ============================================================================
# 💡 역할:
# 클러스터의 노드 수를 자동으로 조절합니다.
#
# 동작 방식:
# 1. Pod가 스케줄링되지 못함 (노드 리소스 부족)
#    → Cluster Autoscaler가 감지
#    → 새 노드 추가!
#
# 2. 노드가 비어있음 (Pod가 거의 없음)
#    → 해당 노드의 Pod를 다른 노드로 이동
#    → 빈 노드 제거!

# IAM 정책
resource "aws_iam_policy" "cluster_autoscaler" {
  name = "${var.cluster_name}-cluster-autoscaler-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # 💡 읽기 권한: 현재 상태 파악
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          # 💡 쓰기 권한: 노드 추가/제거
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-cluster-autoscaler-policy"
  }
}

# IRSA 설정
resource "aws_iam_role" "cluster_autoscaler" {
  name = "${var.cluster_name}-cluster-autoscaler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.cluster_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.cluster_oidc_provider_url}:aud" = "sts.amazonaws.com"
          "${var.cluster_oidc_provider_url}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
        }
      }
    }]
  })

  tags = {
    Name = "${var.cluster_name}-cluster-autoscaler-role"
  }
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
  role       = aws_iam_role.cluster_autoscaler.name
}

# Helm으로 Cluster Autoscaler 설치
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.34.0"

  # 💡 자동 검색 설정
  # 클러스터 이름으로 관련 Auto Scaling Group을 자동으로 찾습니다.
  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  # IRSA 연결
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler.arn
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_autoscaler]
}
