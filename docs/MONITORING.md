# Monitoring và Alerting Guide

Hướng dẫn chi tiết về monitoring, alerting và observability cho dự án DevOps End-to-End.

## 📊 Tổng quan Monitoring Stack

### Kiến trúc Monitoring

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Application   │    │   Prometheus    │    │    Grafana      │
│   (Node.js)     │───▶│   (Metrics)     │───▶│  (Dashboards)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Kubernetes    │    │  Alertmanager   │    │   Logging       │
│   (cAdvisor)    │    │   (Alerts)      │    │   (Fluentd)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Các thành phần chính

1. **Prometheus**: Metrics collection và storage
2. **Grafana**: Visualization và dashboards
3. **Alertmanager**: Alert routing và notification
4. **Node Exporter**: System metrics
5. **cAdvisor**: Container metrics
6. **kube-state-metrics**: Kubernetes state metrics

## 🎯 Application Metrics

### Custom Metrics từ ứng dụng

Ứng dụng Node.js expose các metrics sau:

```javascript
// HTTP Request Metrics
http_requests_total{method, route, status_code}
http_request_duration_seconds{method, route}

// Application Metrics
active_connections
memory_usage_bytes
cpu_usage_percent
```

### Metrics Endpoints

```bash
# Health check
curl http://localhost:3000/health

# Metrics endpoint
curl http://localhost:3000/metrics

# Application status
curl http://localhost:3000/api/status
```

## 🔧 Prometheus Configuration

### Scrape Configuration

```yaml
scrape_configs:
  # Application metrics
  - job_name: 'devops-app'
    kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
            - production
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        regex: 'devops-app'
        action: keep
      - source_labels: [__meta_kubernetes_endpoint_port_name]
        regex: 'http'
        action: keep

  # Kubernetes API server
  - job_name: 'kubernetes-apiservers'
    kubernetes_sd_configs:
      - role: endpoints
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token

  # Kubernetes nodes
  - job_name: 'kubernetes-nodes'
    kubernetes_sd_configs:
      - role: node
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token

  # Kubernetes pods
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
```

### ServiceMonitor cho Kubernetes

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: devops-app
  namespace: production
spec:
  selector:
    matchLabels:
      app: devops-app
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
```

## 📈 Grafana Dashboards

### 1. Application Dashboard

**Metrics hiển thị:**
- Request rate (requests/second)
- Error rate (errors/second)
- Response time (95th percentile)
- Active connections
- Memory usage
- CPU usage

**Queries:**
```promql
# Request rate
rate(http_requests_total[5m])

# Error rate
rate(http_requests_total{status_code=~"5.."}[5m])

# Response time
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Active connections
active_connections
```

### 2. Kubernetes Cluster Dashboard

**Metrics hiển thị:**
- Node CPU/Memory usage
- Pod status và resource usage
- Deployment replicas
- Service endpoints
- Ingress status

**Queries:**
```promql
# Node CPU usage
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Node Memory usage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Pod status
kube_pod_status_phase

# Deployment replicas
kube_deployment_status_replicas_available
```

### 3. Infrastructure Dashboard

**Metrics hiển thị:**
- Disk usage
- Network I/O
- Load average
- File system usage
- System uptime

**Queries:**
```promql
# Disk usage
(1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100

# Network I/O
rate(node_network_receive_bytes_total[5m])
rate(node_network_transmit_bytes_total[5m])

# Load average
node_load1
node_load5
node_load15
```

## 🚨 Alert Rules

### Application Alerts

```yaml
groups:
- name: devops-app.rules
  rules:
  - alert: HighErrorRate
    expr: rate(http_requests_total{status_code=~"5.."}[5m]) > 0.1
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "High error rate detected"
      description: "Error rate is {{ $value }} errors per second"

  - alert: HighResponseTime
    expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High response time detected"
      description: "95th percentile response time is {{ $value }} seconds"

  - alert: ApplicationDown
    expr: up{job="devops-app"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Application is down"
      description: "Application {{ $labels.instance }} is not responding"
```

### Infrastructure Alerts

```yaml
  - alert: HighCPUUsage
    expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High CPU usage detected"
      description: "CPU usage is {{ $value }}% on node {{ $labels.instance }}"

  - alert: HighMemoryUsage
    expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High memory usage detected"
      description: "Memory usage is {{ $value }}% on node {{ $labels.instance }}"

  - alert: DiskSpaceLow
    expr: (1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100 > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Low disk space"
      description: "Disk usage is {{ $value }}% on {{ $labels.instance }}"
```

### Kubernetes Alerts

```yaml
  - alert: PodCrashLooping
    expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Pod is crash looping"
      description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is crash looping"

  - alert: PodNotReady
    expr: kube_pod_status_phase{phase!="Running",phase!="Succeeded"} > 0
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Pod is not ready"
      description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is not ready"

  - alert: KubernetesNodeNotReady
    expr: kube_node_status_condition{condition="Ready",status="true"} == 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Kubernetes node not ready"
      description: "Node {{ $labels.node }} is not ready"
```

## 📧 Alertmanager Configuration

### Routing Rules

```yaml
route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'
  routes:
  - match:
      severity: critical
    receiver: 'critical-alerts'
    group_wait: 5s
    repeat_interval: 5m
  - match:
      severity: warning
    receiver: 'warning-alerts'
    group_wait: 30s
    repeat_interval: 30m
```

### Notification Channels

#### Email Configuration

```yaml
receivers:
- name: 'critical-alerts'
  email_configs:
  - to: 'devops-team@yourcompany.com'
    subject: '[CRITICAL] {{ .GroupLabels.alertname }}'
    body: |
      {{ range .Alerts }}
      Alert: {{ .Annotations.summary }}
      Description: {{ .Annotations.description }}
      Severity: {{ .Labels.severity }}
      Instance: {{ .Labels.instance }}
      {{ end }}
```

#### Slack Configuration

```yaml
- name: 'warning-alerts'
  slack_configs:
  - api_url: 'YOUR_SLACK_WEBHOOK_URL'
    channel: '#alerts-warning'
    title: 'Warning Alert: {{ .GroupLabels.alertname }}'
    text: |
      {{ range .Alerts }}
      *Alert:* {{ .Annotations.summary }}
      *Description:* {{ .Annotations.description }}
      *Severity:* {{ .Labels.severity }}
      *Instance:* {{ .Labels.instance }}
      {{ end }}
```

#### PagerDuty Configuration

```yaml
- name: 'pagerduty'
  pagerduty_configs:
  - routing_key: 'YOUR_PAGERDUTY_INTEGRATION_KEY'
    description: 'High Error Rate Detected'
    details:
      summary: 'High error rate detected in production'
      description: 'Error rate is above threshold'
      severity: 'critical'
```

## 🔍 Monitoring Best Practices

### 1. Metrics Naming Convention

```promql
# Good naming
http_requests_total
http_request_duration_seconds
memory_usage_bytes

# Bad naming
requests
duration
memory
```

### 2. Label Usage

```promql
# Use meaningful labels
http_requests_total{method="GET", route="/api/users", status_code="200"}

# Avoid high cardinality labels
http_requests_total{user_id="12345"}  # Bad - high cardinality
```

### 3. Alert Thresholds

```yaml
# Graduated thresholds
- alert: HighCPUUsage
  expr: cpu_usage_percent > 70
  labels:
    severity: warning

- alert: CriticalCPUUsage
  expr: cpu_usage_percent > 90
  labels:
    severity: critical
```

### 4. Dashboard Design

- **Golden Signals**: Latency, Traffic, Errors, Saturation
- **RED Method**: Rate, Errors, Duration
- **USE Method**: Utilization, Saturation, Errors

## 🛠️ Troubleshooting Monitoring

### Common Issues

#### 1. Metrics không được scrape

```bash
# Kiểm tra ServiceMonitor
kubectl get servicemonitor -n production

# Kiểm tra Prometheus targets
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Truy cập http://localhost:9090/targets
```

#### 2. Alerts không được gửi

```bash
# Kiểm tra Alertmanager configuration
kubectl get configmap alertmanager-config -n monitoring -o yaml

# Kiểm tra Alertmanager logs
kubectl logs deployment/alertmanager -n monitoring

# Test alert
kubectl port-forward svc/alertmanager 9093:9093 -n monitoring
# Truy cập http://localhost:9093
```

#### 3. Grafana không hiển thị data

```bash
# Kiểm tra Grafana datasource
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# Truy cập http://localhost:3000 và kiểm tra datasource

# Kiểm tra Prometheus queries
# Test query trực tiếp trên Prometheus
```

### Debug Commands

```bash
# Kiểm tra Prometheus targets
curl http://localhost:9090/api/v1/targets

# Kiểm tra alert rules
curl http://localhost:9090/api/v1/rules

# Kiểm tra active alerts
curl http://localhost:9093/api/v1/alerts

# Test metrics endpoint
curl http://localhost:3000/metrics
```

## 📊 Performance Tuning

### Prometheus Optimization

```yaml
# Prometheus configuration
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'devops-demo'

# Storage configuration
storage:
  tsdb:
    retention.time: 15d
    retention.size: 50GB
```

### Grafana Optimization

```yaml
# Grafana configuration
grafana:
  persistence:
    enabled: true
    size: 10Gi
  resources:
    requests:
      memory: 1Gi
      cpu: 500m
    limits:
      memory: 2Gi
      cpu: 1000m
```

## 📚 Additional Resources

- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/best-practices/)
- [Alertmanager Best Practices](https://prometheus.io/docs/alerting/latest/best-practices/)
- [Kubernetes Monitoring Guide](https://kubernetes.io/docs/tasks/debug-application-cluster/resource-usage-monitoring/)
