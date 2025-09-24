#!/bin/bash

# DevOps End-to-End Deployment Script
# This script automates the deployment of the entire stack

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="us-west-2"
CLUSTER_NAME="devops-demo-production"
NAMESPACE="production"
MONITORING_NAMESPACE="monitoring"
IMAGE_REPO="ghcr.io/your-org/devops-end2end"
IMAGE_TAG="latest"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if required tools are installed
    local tools=("aws" "kubectl" "helm" "terraform" "docker")
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "All prerequisites are met"
}

deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd terraform
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    terraform plan -out=tfplan
    
    # Apply deployment
    terraform apply tfplan
    
    # Get outputs
    terraform output -json > ../outputs.json
    
    cd ..
    
    log_success "Infrastructure deployed successfully"
}

configure_kubectl() {
    log_info "Configuring kubectl..."
    
    aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
    
    # Verify cluster access
    if kubectl get nodes &> /dev/null; then
        log_success "kubectl configured successfully"
    else
        log_error "Failed to access cluster"
        exit 1
    fi
}

deploy_ingress_controller() {
    log_info "Deploying NGINX Ingress Controller..."
    
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml
    
    # Wait for ingress controller to be ready
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s
    
    log_success "NGINX Ingress Controller deployed"
}

deploy_monitoring() {
    log_info "Deploying monitoring stack..."
    
    # Create monitoring namespace
    kubectl create namespace $MONITORING_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy monitoring stack
    kubectl apply -f monitoring/kube-prometheus-stack.yaml
    kubectl apply -f monitoring/prometheus-config.yaml
    kubectl apply -f monitoring/alertmanager-config.yaml
    kubectl apply -f monitoring/prometheus-rules.yaml
    
    # Wait for monitoring pods to be ready
    kubectl wait --namespace $MONITORING_NAMESPACE \
        --for=condition=ready pod \
        --selector=app=prometheus \
        --timeout=300s
    
    kubectl wait --namespace $MONITORING_NAMESPACE \
        --for=condition=ready pod \
        --selector=app=grafana \
        --timeout=300s
    
    kubectl wait --namespace $MONITORING_NAMESPACE \
        --for=condition=ready pod \
        --selector=app=alertmanager \
        --timeout=300s
    
    log_success "Monitoring stack deployed"
}

build_and_push_image() {
    log_info "Building and pushing Docker image..."
    
    # Build image
    docker build -t $IMAGE_REPO:$IMAGE_TAG .
    
    # Tag for latest
    docker tag $IMAGE_REPO:$IMAGE_TAG $IMAGE_REPO:latest
    
    # Push image (requires GitHub token)
    if [ -z "$GITHUB_TOKEN" ]; then
        log_warning "GITHUB_TOKEN not set. Skipping image push."
        log_warning "Please set GITHUB_TOKEN and push manually:"
        log_warning "echo \$GITHUB_TOKEN | docker login ghcr.io -u your-username --password-stdin"
        log_warning "docker push $IMAGE_REPO:$IMAGE_TAG"
    else
        echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_USERNAME --password-stdin
        docker push $IMAGE_REPO:$IMAGE_TAG
        docker push $IMAGE_REPO:latest
        log_success "Docker image pushed successfully"
    fi
}

deploy_application() {
    log_info "Deploying application with Helm..."
    
    cd helm/devops-app
    
    # Update dependencies
    helm dependency update
    
    # Deploy application
    helm upgrade --install devops-app . \
        --namespace $NAMESPACE \
        --create-namespace \
        --set image.repository=$IMAGE_REPO \
        --set image.tag=$IMAGE_TAG \
        --set environment=production \
        --set ingress.enabled=true \
        --set ingress.hosts[0].host=devops-app.example.com \
        --wait \
        --timeout=300s
    
    cd ../..
    
    log_success "Application deployed successfully"
}

create_ingress() {
    log_info "Creating Ingress resource..."
    
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: devops-app-ingress
  namespace: $NAMESPACE
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
    
    log_success "Ingress created successfully"
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check pods
    kubectl get pods -n $NAMESPACE
    
    # Check services
    kubectl get svc -n $NAMESPACE
    
    # Check ingress
    kubectl get ingress -n $NAMESPACE
    
    # Test health endpoint
    log_info "Testing health endpoint..."
    kubectl port-forward svc/devops-app 8080:80 -n $NAMESPACE &
    PORT_FORWARD_PID=$!
    
    sleep 5
    
    if curl -f http://localhost:8080/health &> /dev/null; then
        log_success "Health check passed"
    else
        log_error "Health check failed"
    fi
    
    # Kill port forward
    kill $PORT_FORWARD_PID 2>/dev/null || true
    
    log_success "Deployment verification completed"
}

show_access_info() {
    log_info "Deployment completed! Access information:"
    
    echo ""
    echo "🌐 Application URLs:"
    echo "   - Health: http://devops-app.example.com/health"
    echo "   - Metrics: http://devops-app.example.com/metrics"
    echo "   - API: http://devops-app.example.com/api/users"
    
    echo ""
    echo "📊 Monitoring URLs (Port Forward Required):"
    echo "   - Grafana: kubectl port-forward svc/grafana 3000:3000 -n $MONITORING_NAMESPACE"
    echo "   - Prometheus: kubectl port-forward svc/prometheus 9090:9090 -n $MONITORING_NAMESPACE"
    echo "   - Alertmanager: kubectl port-forward svc/alertmanager 9093:9093 -n $MONITORING_NAMESPACE"
    
    echo ""
    echo "🔧 Useful Commands:"
    echo "   - View logs: kubectl logs -f deployment/devops-app -n $NAMESPACE"
    echo "   - Scale app: kubectl scale deployment devops-app --replicas=3 -n $NAMESPACE"
    echo "   - Check HPA: kubectl get hpa -n $NAMESPACE"
    echo "   - View events: kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
    
    echo ""
    echo "📚 Documentation:"
    echo "   - Deployment Guide: docs/DEPLOYMENT.md"
    echo "   - Monitoring Guide: docs/MONITORING.md"
    echo "   - README: README.md"
}

cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f outputs.json
    rm -f terraform/tfplan
}

# Main execution
main() {
    log_info "Starting DevOps End-to-End deployment..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-infrastructure)
                SKIP_INFRASTRUCTURE=true
                shift
                ;;
            --skip-monitoring)
                SKIP_MONITORING=true
                shift
                ;;
            --skip-image-build)
                SKIP_IMAGE_BUILD=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --skip-infrastructure    Skip infrastructure deployment"
                echo "  --skip-monitoring        Skip monitoring stack deployment"
                echo "  --skip-image-build       Skip Docker image build and push"
                echo "  --help                   Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Execute deployment steps
    check_prerequisites
    
    if [ "$SKIP_INFRASTRUCTURE" != "true" ]; then
        deploy_infrastructure
        configure_kubectl
        deploy_ingress_controller
    fi
    
    if [ "$SKIP_MONITORING" != "true" ]; then
        deploy_monitoring
    fi
    
    if [ "$SKIP_IMAGE_BUILD" != "true" ]; then
        build_and_push_image
    fi
    
    deploy_application
    create_ingress
    verify_deployment
    show_access_info
    
    log_success "Deployment completed successfully! 🎉"
}

# Run main function
main "$@"
