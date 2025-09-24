# DevOps End-to-End Project Makefile
# This Makefile provides convenient commands for managing the project

.PHONY: help install build test deploy clean lint format

# Default target
help: ## Show this help message
	@echo "DevOps End-to-End Project"
	@echo "========================="
	@echo ""
	@echo "Available commands:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Development commands
install: ## Install dependencies
	npm install

dev: ## Start development server
	npm run dev

build: ## Build Docker image
	docker build -t devops-end2end-app:latest .

run: ## Run Docker container locally
	docker run -p 3000:3000 devops-end2end-app:latest

# Testing commands
test: ## Run tests
	npm test

lint: ## Run linting
	npm run lint

format: ## Format code
	npx prettier --write "src/**/*.js"

# Infrastructure commands
terraform-init: ## Initialize Terraform
	cd terraform && terraform init

terraform-plan: ## Plan Terraform deployment
	cd terraform && terraform plan

terraform-apply: ## Apply Terraform configuration
	cd terraform && terraform apply

terraform-destroy: ## Destroy Terraform infrastructure
	cd terraform && terraform destroy

# Kubernetes commands
kube-config: ## Configure kubectl for EKS
	aws eks update-kubeconfig --region us-west-2 --name devops-demo-production

kube-status: ## Check Kubernetes cluster status
	kubectl get nodes
	kubectl get pods --all-namespaces

# Monitoring commands
monitoring-deploy: ## Deploy monitoring stack
	kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f monitoring/kube-prometheus-stack.yaml
	kubectl apply -f monitoring/prometheus-config.yaml
	kubectl apply -f monitoring/alertmanager-config.yaml
	kubectl apply -f monitoring/prometheus-rules.yaml

monitoring-status: ## Check monitoring stack status
	kubectl get pods -n monitoring
	kubectl get svc -n monitoring

monitoring-port-forward: ## Port forward monitoring services
	@echo "Port forwarding monitoring services..."
	@echo "Grafana: http://localhost:3000 (admin/admin123)"
	@echo "Prometheus: http://localhost:9090"
	@echo "Alertmanager: http://localhost:9093"
	@echo ""
	@echo "Press Ctrl+C to stop"
	kubectl port-forward svc/grafana 3000:3000 -n monitoring &
	kubectl port-forward svc/prometheus 9090:9090 -n monitoring &
	kubectl port-forward svc/alertmanager 9093:9093 -n monitoring &
	wait

# Helm commands
helm-deps: ## Update Helm dependencies
	cd helm/devops-app && helm dependency update

helm-deploy: ## Deploy application with Helm
	cd helm/devops-app && helm upgrade --install devops-app . \
		--namespace production \
		--create-namespace \
		--set image.repository=ghcr.io/your-org/devops-end2end \
		--set image.tag=latest \
		--set environment=production

helm-status: ## Check Helm deployment status
	helm list -n production
	kubectl get pods -n production

helm-uninstall: ## Uninstall Helm deployment
	helm uninstall devops-app -n production

# Application commands
app-deploy: ## Deploy application
	./scripts/deploy.sh

app-test: ## Test application deployment
	./scripts/test.sh

app-logs: ## View application logs
	kubectl logs -f deployment/devops-app -n production

app-scale: ## Scale application
	@read -p "Enter number of replicas: " replicas; \
	kubectl scale deployment devops-app --replicas=$$replicas -n production

# CI/CD commands
ci-test: ## Run CI pipeline locally
	npm run lint
	npm test
	docker build -t devops-end2end-app:latest .

ci-security: ## Run security scans
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy image devops-end2end-app:latest

# Utility commands
clean: ## Clean up temporary files
	rm -f outputs.json
	rm -f terraform/tfplan
	docker system prune -f

logs: ## View all application logs
	kubectl logs -f deployment/devops-app -n production

events: ## View Kubernetes events
	kubectl get events -n production --sort-by='.lastTimestamp'

status: ## Show overall project status
	@echo "=== Kubernetes Cluster Status ==="
	kubectl get nodes
	@echo ""
	@echo "=== Application Status ==="
	kubectl get pods,svc,ingress -n production
	@echo ""
	@echo "=== Monitoring Status ==="
	kubectl get pods,svc -n monitoring
	@echo ""
	@echo "=== Helm Releases ==="
	helm list -A

# Full deployment
deploy-all: ## Deploy entire stack
	@echo "Starting full deployment..."
	$(MAKE) terraform-init
	$(MAKE) terraform-apply
	$(MAKE) kube-config
	$(MAKE) monitoring-deploy
	$(MAKE) helm-deps
	$(MAKE) helm-deploy
	@echo "Deployment completed!"

# Full cleanup
clean-all: ## Clean up entire stack
	@echo "Cleaning up entire stack..."
	$(MAKE) helm-uninstall
	$(MAKE) terraform-destroy
	$(MAKE) clean
	@echo "Cleanup completed!"

# Development workflow
dev-setup: ## Setup development environment
	$(MAKE) install
	$(MAKE) build
	@echo "Development environment ready!"

# Production workflow
prod-deploy: ## Deploy to production
	@echo "Deploying to production..."
	$(MAKE) ci-test
	$(MAKE) ci-security
	$(MAKE) deploy-all
	$(MAKE) app-test
	@echo "Production deployment completed!"

# Quick start
quick-start: ## Quick start for development
	$(MAKE) dev-setup
	$(MAKE) run

# Documentation
docs: ## Generate documentation
	@echo "Documentation is available in the docs/ directory"
	@echo "- README.md: Main project documentation"
	@echo "- docs/DEPLOYMENT.md: Deployment guide"
	@echo "- docs/MONITORING.md: Monitoring guide"

# Health check
health: ## Check application health
	@echo "Checking application health..."
	kubectl port-forward svc/devops-app 8080:80 -n production &
	@sleep 5
	@curl -f http://localhost:8080/health || echo "Health check failed"
	@pkill -f "kubectl port-forward" 2>/dev/null || true

# Load test
load-test: ## Run load test
	@echo "Running load test..."
	kubectl port-forward svc/devops-app 8080:80 -n production &
	@sleep 5
	@if command -v hey >/dev/null 2>&1; then \
		hey -n 100 -c 10 http://localhost:8080/api/load?iterations=10000; \
	else \
		echo "Installing hey load testing tool..."; \
		go install github.com/rakyll/hey@latest; \
		hey -n 100 -c 10 http://localhost:8080/api/load?iterations=10000; \
	fi
	@pkill -f "kubectl port-forward" 2>/dev/null || true
