# DevOps End-to-End Demo Project

## 🏗️ Kiến trúc tổng quan

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Application   │    │   CI/CD Pipeline│    │   Infrastructure│
│   (Node.js)     │───▶│ (GitHub Actions)│───▶│   (Terraform)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Container     │    │   Deployment    │    │   EKS Cluster   │
│   (Docker)      │    │   (Helm)        │    │   (AWS)         │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Monitoring    │    │   Alerting      │    │   Logging       │
│ (Prometheus)    │    │(Alertmanager)   │    │   (Grafana)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📋 Các thành phần chính

### 1. Ứng dụng Web (Node.js + Express)
- **Framework**: Express.js với middleware bảo mật
- **Metrics**: Prometheus metrics tích hợp sẵn
- **Health checks**: Endpoint `/health` và `/metrics`
- **Features**: CORS, Helmet, Morgan logging

### 2. Containerization (Docker)
- **Multi-stage build** để tối ưu kích thước image
- **Security**: Non-root user, minimal base image
- **Health checks** tích hợp
- **Production-ready** configuration

### 3. CI/CD Pipeline (GitHub Actions)
- **Testing**: Linting, unit tests, security scanning
- **Build & Push**: Multi-arch Docker images
- **Deploy**: Staging và Production environments
- **Security**: Trivy vulnerability scanning

### 4. Infrastructure as Code (Terraform)
- **EKS Cluster** với managed node groups
- **VPC** với public/private subnets
- **IAM roles** và policies
- **Auto Scaling** và Load Balancer

### 5. Deployment (Helm)
- **Helm Chart** với templates đầy đủ
- **ConfigMaps** và Secrets management
- **HPA** (Horizontal Pod Autoscaler)
- **Network Policies** cho security

### 6. Monitoring (Prometheus + Grafana)
- **Prometheus** scraping metrics từ ứng dụng
- **Grafana** dashboards cho visualization
- **ServiceMonitor** cho Kubernetes integration
- **Custom metrics** cho business logic

### 7. Alerting (Alertmanager)
- **Multi-channel alerts**: Email, Slack, PagerDuty
- **Alert rules** cho infrastructure và application
- **Templates** cho notification formatting
- **Escalation policies**

## 🚀 Hướng dẫn triển khai

### Prerequisites

1. **AWS CLI** đã được cấu hình
2. **kubectl** đã được cài đặt
3. **Helm** v3.x
4. **Terraform** v1.6+
5. **Docker** và **Docker Compose**
6. **Node.js** v18+

### Bước 1: Clone repository

```bash
git clone https://github.com/your-org/devops-end2end.git
cd devops-end2end
```

### Bước 2: Cấu hình AWS và Terraform

```bash
# Cấu hình AWS credentials
aws configure

# Khởi tạo Terraform
cd terraform
terraform init
terraform plan
terraform apply
```

### Bước 3: Cấu hình kubectl

```bash
# Cập nhật kubeconfig
aws eks update-kubeconfig --region us-west-2 --name devops-demo-production

# Kiểm tra cluster
kubectl get nodes
```

### Bước 4: Deploy monitoring stack

```bash
# Tạo namespace monitoring
kubectl create namespace monitoring

# Deploy Prometheus, Grafana, Alertmanager
kubectl apply -f monitoring/kube-prometheus-stack.yaml
kubectl apply -f monitoring/prometheus-config.yaml
kubectl apply -f monitoring/alertmanager-config.yaml
kubectl apply -f monitoring/prometheus-rules.yaml
```

### Bước 5: Deploy ứng dụng với Helm

```bash
# Cài đặt dependencies
helm dependency update helm/devops-app

# Deploy ứng dụng
helm upgrade --install devops-app ./helm/devops-app \
  --namespace production \
  --create-namespace \
  --set image.repository=ghcr.io/your-org/devops-end2end \
  --set image.tag=latest \
  --set environment=production
```

### Bước 6: Cấu hình Ingress (tùy chọn)

```bash
# Cài đặt NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml

# Cấu hình Ingress
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: devops-app-ingress
  namespace: production
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: devops-app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: devops-app
            port:
              number: 80
EOF
```

## 🔧 Cấu hình CI/CD

### GitHub Secrets cần thiết

```bash
# AWS Credentials
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key

# Container Registry
GITHUB_TOKEN=your-github-token

# Alerting (tùy chọn)
SLACK_WEBHOOK=your-slack-webhook-url
PAGERDUTY_INTEGRATION_KEY=your-pagerduty-key
```

### Workflow triggers

- **Push to main**: Deploy to production
- **Push to develop**: Deploy to staging
- **Pull Request**: Run tests and security scans

## 📊 Monitoring và Alerting

### Prometheus Metrics

Ứng dụng expose các metrics sau:

- `http_requests_total`: Tổng số HTTP requests
- `http_request_duration_seconds`: Thời gian response
- `active_connections`: Số kết nối đang hoạt động

### Grafana Dashboards

1. **Application Dashboard**: Metrics từ ứng dụng
2. **Kubernetes Dashboard**: Cluster và pod metrics
3. **Node Exporter Dashboard**: System metrics

### Alert Rules

- **High Error Rate**: > 10% error rate trong 5 phút
- **High Response Time**: 95th percentile > 1 giây
- **Pod Crash Looping**: Pod restart liên tục
- **High CPU/Memory Usage**: > 80% utilization

## 🛡️ Security

### Container Security
- Non-root user trong container
- Minimal base image (Alpine Linux)
- Security scanning với Trivy
- Network policies

### Kubernetes Security
- RBAC (Role-Based Access Control)
- Pod Security Standards
- Network policies
- Secrets management

### Infrastructure Security
- VPC với private subnets
- Security groups
- IAM roles với least privilege
- Encryption at rest và in transit

## 📁 Cấu trúc thư mục

```
devops-end2end/
├── src/                          # Source code ứng dụng
│   └── app.js                   # Main application file
├── terraform/                    # Infrastructure as Code
│   ├── main.tf                  # Main Terraform configuration
│   ├── variables.tf             # Variables definition
│   ├── outputs.tf               # Outputs definition
│   └── terraform.tfvars.example # Example variables
├── helm/                        # Helm charts
│   └── devops-app/             # Application Helm chart
│       ├── Chart.yaml          # Chart metadata
│       ├── values.yaml         # Default values
│       └── templates/          # Kubernetes templates
├── monitoring/                  # Monitoring configuration
│   ├── prometheus-config.yaml  # Prometheus configuration
│   ├── alertmanager-config.yaml # Alertmanager configuration
│   ├── prometheus-rules.yaml   # Alert rules
│   └── grafana-dashboard.json  # Grafana dashboard
├── .github/                     # GitHub Actions workflows
│   └── workflows/
│       ├── ci-cd.yml           # Main CI/CD pipeline
│       └── terraform.yml       # Infrastructure pipeline
├── Dockerfile                   # Container definition
├── package.json                 # Node.js dependencies
└── README.md                    # This file
```

## 🔍 Troubleshooting

### Kiểm tra trạng thái ứng dụng

```bash
# Kiểm tra pods
kubectl get pods -n production

# Kiểm tra logs
kubectl logs -f deployment/devops-app -n production

# Kiểm tra services
kubectl get svc -n production

# Kiểm tra ingress
kubectl get ingress -n production
```

### Kiểm tra monitoring

```bash
# Port forward để truy cập Grafana
kubectl port-forward svc/grafana 3000:3000 -n monitoring

# Port forward để truy cập Prometheus
kubectl port-forward svc/prometheus 9090:9090 -n monitoring

# Port forward để truy cập Alertmanager
kubectl port-forward svc/alertmanager 9093:9093 -n monitoring
```

### Debugging

```bash
# Kiểm tra events
kubectl get events -n production --sort-by='.lastTimestamp'

# Kiểm tra resource usage
kubectl top pods -n production
kubectl top nodes

# Kiểm tra HPA
kubectl get hpa -n production
```

## 📚 Tài liệu tham khảo

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)