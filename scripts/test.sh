#!/bin/bash

# DevOps End-to-End Testing Script
# This script runs various tests to verify the deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="production"
MONITORING_NAMESPACE="monitoring"
APP_URL="http://localhost:8080"
GRAFANA_URL="http://localhost:3000"
PROMETHEUS_URL="http://localhost:9090"
ALERTMANAGER_URL="http://localhost:9093"

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

test_kubernetes_resources() {
    log_info "Testing Kubernetes resources..."
    
    # Test pods
    if kubectl get pods -n $NAMESPACE | grep -q "Running"; then
        log_success "Application pods are running"
    else
        log_error "Application pods are not running"
        return 1
    fi
    
    # Test services
    if kubectl get svc -n $NAMESPACE | grep -q "devops-app"; then
        log_success "Application service is available"
    else
        log_error "Application service is not available"
        return 1
    fi
    
    # Test ingress
    if kubectl get ingress -n $NAMESPACE | grep -q "devops-app-ingress"; then
        log_success "Ingress is configured"
    else
        log_warning "Ingress is not configured"
    fi
    
    # Test HPA
    if kubectl get hpa -n $NAMESPACE | grep -q "devops-app"; then
        log_success "HPA is configured"
    else
        log_warning "HPA is not configured"
    fi
}

test_application_endpoints() {
    log_info "Testing application endpoints..."
    
    # Start port forward
    kubectl port-forward svc/devops-app 8080:80 -n $NAMESPACE &
    PORT_FORWARD_PID=$!
    
    # Wait for port forward to be ready
    sleep 5
    
    # Test health endpoint
    if curl -f -s $APP_URL/health | grep -q "healthy"; then
        log_success "Health endpoint is working"
    else
        log_error "Health endpoint is not working"
        kill $PORT_FORWARD_PID 2>/dev/null || true
        return 1
    fi
    
    # Test metrics endpoint
    if curl -f -s $APP_URL/metrics | grep -q "http_requests_total"; then
        log_success "Metrics endpoint is working"
    else
        log_error "Metrics endpoint is not working"
        kill $PORT_FORWARD_PID 2>/dev/null || true
        return 1
    fi
    
    # Test API endpoints
    if curl -f -s $APP_URL/api/users | grep -q "John Doe"; then
        log_success "API endpoints are working"
    else
        log_error "API endpoints are not working"
        kill $PORT_FORWARD_PID 2>/dev/null || true
        return 1
    fi
    
    # Test load endpoint
    if curl -f -s "$APP_URL/api/load?iterations=1000" | grep -q "result"; then
        log_success "Load endpoint is working"
    else
        log_error "Load endpoint is not working"
        kill $PORT_FORWARD_PID 2>/dev/null || true
        return 1
    fi
    
    # Kill port forward
    kill $PORT_FORWARD_PID 2>/dev/null || true
}

test_monitoring_stack() {
    log_info "Testing monitoring stack..."
    
    # Test Prometheus
    kubectl port-forward svc/prometheus 9090:9090 -n $MONITORING_NAMESPACE &
    PROMETHEUS_PID=$!
    sleep 5
    
    if curl -f -s $PROMETHEUS_URL/api/v1/targets | grep -q "devops-app"; then
        log_success "Prometheus is scraping application metrics"
    else
        log_warning "Prometheus is not scraping application metrics"
    fi
    
    kill $PROMETHEUS_PID 2>/dev/null || true
    
    # Test Grafana
    kubectl port-forward svc/grafana 3000:3000 -n $MONITORING_NAMESPACE &
    GRAFANA_PID=$!
    sleep 5
    
    if curl -f -s $GRAFANA_URL/api/health | grep -q "ok"; then
        log_success "Grafana is accessible"
    else
        log_warning "Grafana is not accessible"
    fi
    
    kill $GRAFANA_PID 2>/dev/null || true
    
    # Test Alertmanager
    kubectl port-forward svc/alertmanager 9093:9093 -n $MONITORING_NAMESPACE &
    ALERTMANAGER_PID=$!
    sleep 5
    
    if curl -f -s $ALERTMANAGER_URL/api/v1/status | grep -q "ready"; then
        log_success "Alertmanager is ready"
    else
        log_warning "Alertmanager is not ready"
    fi
    
    kill $ALERTMANAGER_PID 2>/dev/null || true
}

test_load_scenario() {
    log_info "Running load test scenario..."
    
    # Start port forward
    kubectl port-forward svc/devops-app 8080:80 -n $NAMESPACE &
    PORT_FORWARD_PID=$!
    sleep 5
    
    # Install hey if not available
    if ! command -v hey &> /dev/null; then
        log_info "Installing hey load testing tool..."
        go install github.com/rakyll/hey@latest
    fi
    
    # Run load test
    log_info "Running load test with 100 requests and 10 concurrent users..."
    hey -n 100 -c 10 $APP_URL/api/load?iterations=10000
    
    # Check if HPA is working
    log_info "Checking HPA status..."
    kubectl get hpa -n $NAMESPACE
    
    # Kill port forward
    kill $PORT_FORWARD_PID 2>/dev/null || true
    
    log_success "Load test completed"
}

test_alerting() {
    log_info "Testing alerting system..."
    
    # Start port forward for Alertmanager
    kubectl port-forward svc/alertmanager 9093:9093 -n $MONITORING_NAMESPACE &
    ALERTMANAGER_PID=$!
    sleep 5
    
    # Check if alerts are configured
    if curl -f -s $ALERTMANAGER_URL/api/v1/alerts | grep -q "alerts"; then
        log_success "Alerting system is configured"
    else
        log_warning "No alerts are currently firing"
    fi
    
    # Kill port forward
    kill $ALERTMANAGER_PID 2>/dev/null || true
}

test_security() {
    log_info "Testing security configurations..."
    
    # Test network policies
    if kubectl get networkpolicy -n $NAMESPACE | grep -q "devops-app"; then
        log_success "Network policies are configured"
    else
        log_warning "Network policies are not configured"
    fi
    
    # Test pod security context
    if kubectl get deployment devops-app -n $NAMESPACE -o yaml | grep -q "runAsNonRoot: true"; then
        log_success "Pod security context is configured"
    else
        log_warning "Pod security context is not properly configured"
    fi
    
    # Test service account
    if kubectl get deployment devops-app -n $NAMESPACE -o yaml | grep -q "serviceAccountName"; then
        log_success "Service account is configured"
    else
        log_warning "Service account is not configured"
    fi
}

test_backup_and_recovery() {
    log_info "Testing backup and recovery procedures..."
    
    # Test Helm release backup
    if helm list -n $NAMESPACE | grep -q "devops-app"; then
        log_success "Helm release is available"
        
        # Test rollback capability
        log_info "Testing rollback capability..."
        helm history devops-app -n $NAMESPACE
        log_success "Rollback capability is available"
    else
        log_error "Helm release is not available"
        return 1
    fi
    
    # Test ConfigMap backup
    if kubectl get configmap -n $NAMESPACE | grep -q "devops-app"; then
        log_success "ConfigMaps are available"
    else
        log_warning "ConfigMaps are not available"
    fi
}

generate_test_report() {
    log_info "Generating test report..."
    
    local report_file="test-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "DevOps End-to-End Test Report"
        echo "Generated: $(date)"
        echo "=================================="
        echo ""
        
        echo "Kubernetes Resources:"
        kubectl get pods,svc,ingress,hpa -n $NAMESPACE
        echo ""
        
        echo "Monitoring Stack:"
        kubectl get pods,svc -n $MONITORING_NAMESPACE
        echo ""
        
        echo "Application Logs (last 10 lines):"
        kubectl logs deployment/devops-app -n $NAMESPACE --tail=10
        echo ""
        
        echo "Events:"
        kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10
        echo ""
        
    } > $report_file
    
    log_success "Test report generated: $report_file"
}

cleanup() {
    log_info "Cleaning up test processes..."
    
    # Kill any remaining port forwards
    pkill -f "kubectl port-forward" 2>/dev/null || true
}

# Main execution
main() {
    log_info "Starting DevOps End-to-End testing..."
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Parse command line arguments
    local run_load_test=false
    local run_security_test=false
    local run_backup_test=false
    local generate_report=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --load-test)
                run_load_test=true
                shift
                ;;
            --security-test)
                run_security_test=true
                shift
                ;;
            --backup-test)
                run_backup_test=true
                shift
                ;;
            --generate-report)
                generate_report=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --load-test        Run load testing scenario"
                echo "  --security-test    Run security tests"
                echo "  --backup-test      Run backup and recovery tests"
                echo "  --generate-report  Generate detailed test report"
                echo "  --help             Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute tests
    test_kubernetes_resources
    test_application_endpoints
    test_monitoring_stack
    test_alerting
    
    if [ "$run_load_test" = "true" ]; then
        test_load_scenario
    fi
    
    if [ "$run_security_test" = "true" ]; then
        test_security
    fi
    
    if [ "$run_backup_test" = "true" ]; then
        test_backup_and_recovery
    fi
    
    if [ "$generate_report" = "true" ]; then
        generate_test_report
    fi
    
    log_success "All tests completed successfully! 🎉"
}

# Run main function
main "$@"
