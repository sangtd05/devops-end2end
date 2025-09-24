# Deployment Guide

Hướng dẫn chi tiết để triển khai dự án DevOps End-to-End.

## 📋 Prerequisites

### 1. Công cụ cần thiết

```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

### 2. Cấu hình AWS

```bash
# Cấu hình AWS credentials
aws configure

# Kiểm tra cấu hình
aws sts get-caller-identity

# Tạo S3 bucket cho Terraform state (nếu chưa có)
aws s3 mb s3://devops-end2end-terraform-state --region us-west-2
```

## 🏗️ Infrastructure Deployment

### Bước 1: Deploy EKS Cluster với Terraform

```bash
cd terraform

# Khởi tạo Terraform
terraform init

# Xem kế hoạch triển khai
terraform plan

# Triển khai infrastructure
terraform apply

# Lưu outputs
terraform output -json > ../outputs.json
```

### Bước 2: Cấu hình kubectl

```bash
# Cập nhật kubeconfig
aws eks update-kubeconfig --region us-west-2 --name devops-demo-production

# Kiểm tra cluster
kubectl get nodes
kubectl get namespaces
```

### Bước 3: Cài đặt NGINX Ingress Controller

```bash
# Cài đặt NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml

# Kiểm tra ingress controller
kubectl get pods -n ingress-nginx
```

## 📊 Monitoring Stack Deployment

### Bước 1: Deploy Prometheus, Grafana, Alertmanager

```bash
# Tạo namespace monitoring
kubectl create namespace monitoring

# Deploy monitoring stack
kubectl apply -f monitoring/kube-prometheus-stack.yaml

# Deploy Prometheus configuration
kubectl apply -f monitoring/prometheus-config.yaml

# Deploy Alertmanager configuration
kubectl apply -f monitoring/alertmanager-config.yaml

# Deploy alert rules
kubectl apply -f monitoring/prometheus-rules.yaml
```

### Bước 2: Kiểm tra monitoring stack

```bash
# Kiểm tra pods
kubectl get pods -n monitoring

# Port forward để truy cập
kubectl port-forward svc/prometheus 9090:9090 -n monitoring &
kubectl port-forward svc/grafana 3000:3000 -n monitoring &
kubectl port-forward svc/alertmanager 9093:9093 -n monitoring &

# Truy cập:
# Prometheus: http://localhost:9090
# Grafana: http://localhost:3000 (admin/admin123)
# Alertmanager: http://localhost:9093
```

## 🚀 Application Deployment

### Bước 1: Build và push Docker image

```bash
# Build image
docker build -t devops-end2end-app:latest .

# Tag image cho registry
docker tag devops-end2end-app:latest ghcr.io/your-org/devops-end2end:latest

# Push image (cần đăng nhập GitHub Container Registry)
echo $GITHUB_TOKEN | docker login ghcr.io -u your-username --password-stdin
docker push ghcr.io/your-org/devops-end2end:latest
```

### Bước 2: Deploy với Helm

```bash
cd helm/devops-app

# Cài đặt dependencies
helm dependency update

# Deploy ứng dụng
helm upgrade --install devops-app . \
  --namespace production \
  --create-namespace \
  --set image.repository=ghcr.io/your-org/devops-end2end \
  --set image.tag=latest \
  --set environment=production \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=devops-app.example.com
```

### Bước 3: Cấu hình Ingress

```bash
# Tạo Ingress resource
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: devops-app-ingress
  namespace: production
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/rewrite-target: /
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

## 🔧 CI/CD Pipeline Setup

### Bước 1: Cấu hình GitHub Secrets

Trong GitHub repository, thêm các secrets sau:

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

### Bước 2: Cấu hình GitHub Environments

1. Tạo environment `staging`
2. Tạo environment `production`
3. Thêm protection rules nếu cần

### Bước 3: Test CI/CD Pipeline

```bash
# Push code để trigger pipeline
git add .
git commit -m "Initial deployment"
git push origin main
```

## 🧪 Testing Deployment

### Bước 1: Kiểm tra ứng dụng

```bash
# Kiểm tra pods
kubectl get pods -n production

# Kiểm tra services
kubectl get svc -n production

# Kiểm tra ingress
kubectl get ingress -n production

# Test health endpoint
kubectl port-forward svc/devops-app 8080:80 -n production
curl http://localhost:8080/health
```

### Bước 2: Kiểm tra monitoring

```bash
# Kiểm tra Prometheus targets
curl http://localhost:9090/api/v1/targets

# Kiểm tra Grafana dashboards
# Truy cập http://localhost:3000 và import dashboard

# Kiểm tra Alertmanager
curl http://localhost:9093/api/v1/alerts
```

### Bước 3: Load testing

```bash
# Cài đặt hey (load testing tool)
go install github.com/rakyll/hey@latest

# Chạy load test
hey -n 1000 -c 10 http://localhost:8080/api/load?iterations=100000
```

## 🔍 Troubleshooting

### Common Issues

#### 1. Pod không start được

```bash
# Kiểm tra pod status
kubectl describe pod <pod-name> -n production

# Kiểm tra logs
kubectl logs <pod-name> -n production

# Kiểm tra events
kubectl get events -n production --sort-by='.lastTimestamp'
```

#### 2. Service không accessible

```bash
# Kiểm tra service endpoints
kubectl get endpoints -n production

# Kiểm tra service selector
kubectl get svc devops-app -n production -o yaml
```

#### 3. Ingress không hoạt động

```bash
# Kiểm tra ingress controller
kubectl get pods -n ingress-nginx

# Kiểm tra ingress status
kubectl describe ingress devops-app-ingress -n production
```

#### 4. Monitoring không hoạt động

```bash
# Kiểm tra ServiceMonitor
kubectl get servicemonitor -n production

# Kiểm tra Prometheus targets
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Truy cập http://localhost:9090/targets
```

### Debug Commands

```bash
# Kiểm tra resource usage
kubectl top pods -n production
kubectl top nodes

# Kiểm tra HPA
kubectl get hpa -n production
kubectl describe hpa devops-app -n production

# Kiểm tra network policies
kubectl get networkpolicy -n production

# Kiểm tra RBAC
kubectl get roles,rolebindings,clusterroles,clusterrolebindings
```

## 📈 Scaling và Optimization

### Horizontal Pod Autoscaler

```bash
# Kiểm tra HPA status
kubectl get hpa -n production

# Tạo load để test autoscaling
kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -- /bin/sh
# Trong container:
while true; do wget -q -O- http://devops-app.production.svc.cluster.local/api/load; done
```

### Vertical Pod Autoscaler (tùy chọn)

```bash
# Cài đặt VPA
kubectl apply -f https://github.com/kubernetes/autoscaler/releases/download/vertical-pod-autoscaler-0.13.0/vpa-release.yaml

# Tạo VPA cho ứng dụng
kubectl apply -f - <<EOF
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: devops-app-vpa
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: devops-app
  updatePolicy:
    updateMode: "Auto"
EOF
```

## 🔄 Updates và Maintenance

### Rolling Updates

```bash
# Update image
helm upgrade devops-app ./helm/devops-app \
  --set image.tag=v1.1.0 \
  --namespace production

# Rollback nếu cần
helm rollback devops-app 1 --namespace production
```

### Backup và Recovery

```bash
# Backup Helm releases
helm list -n production -o yaml > production-releases-backup.yaml

# Backup ConfigMaps và Secrets
kubectl get configmaps,secrets -n production -o yaml > production-config-backup.yaml

# Backup Terraform state
terraform state pull > terraform-state-backup.json
```

## 📚 Additional Resources

- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
