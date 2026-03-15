#!/bin/bash
# setup-monitoring.sh - Deploy kube-prometheus stack and configure monitoring

set -e

echo "========================================"
echo "Kube-Prometheus Stack Setup"
echo "========================================"
echo ""

# Variables
NAMESPACE="monitoring"
RELEASE_NAME="kube-prometheus-stack"

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: kubectl is not configured. Please configure kubectl first."
    exit 1
fi

# 1. Create monitoring namespace
echo "Creating monitoring namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
echo "✓ Namespace created"

# 2. Add Prometheus Community Helm repository
echo "Adding Prometheus Community Helm repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
echo "✓ Helm repository added"

# 3. Create custom values file for kube-prometheus-stack
echo "Creating custom values file..."
cat > /tmp/prometheus-values.yaml << 'EOF'
# Prometheus Operator Configuration
prometheusOperator:
  enabled: true
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi

# Prometheus Configuration
prometheus:
  enabled: true
  prometheusSpec:
    # Storage configuration
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    
    # Resource limits
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 1000m
        memory: 4Gi
    
    # Retention
    retention: 15d
    retentionSize: "9GB"
    
    # Service monitors
    serviceMonitorSelector:
      matchLabels:
        release: kube-prometheus-stack
    
    # Pod monitors
    podMonitorSelector:
      matchLabels:
        release: kube-prometheus-stack
    
    # Additional scrape configs for custom metrics
    additionalScrapeConfigs:
    - job_name: 'bookstore-api'
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - bookstore
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: bookapp-api
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
    
    - job_name: 'bookstore-ui'
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - bookstore
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: bookapp-ui
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace

  # Ingress configuration (optional)
  ingress:
    enabled: false

  # Service configuration
  service:
    type: ClusterIP
    port: 9090

# Grafana Configuration
grafana:
  enabled: true
  adminPassword: admin123  # Change this in production!
  
  # Persistence
  persistence:
    enabled: true
    size: 5Gi
  
  # Resources
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi
  
  # Service configuration
  service:
    type: LoadBalancer  # For easy access, change to ClusterIP with Ingress in production
    port: 80
  
  # Default dashboards
  defaultDashboardsEnabled: true
  
  # Additional data sources
  additionalDataSources: []
  
  # Grafana ini configuration
  grafana.ini:
    server:
      root_url: "http://localhost:3000"
    security:
      allow_embedding: true
    auth.anonymous:
      enabled: false

# Alertmanager Configuration
alertmanager:
  enabled: true
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi
    
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
  
  service:
    type: ClusterIP
    port: 9093
  
  # Alertmanager configuration
  config:
    global:
      resolve_timeout: 5m
    
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'default'
      routes:
      - match:
          alertname: Watchdog
        receiver: 'null'
      - match:
          severity: critical
        receiver: 'critical'
      - match:
          severity: warning
        receiver: 'warning'
    
    receivers:
    - name: 'null'
    - name: 'default'
      # Add your notification channels here (Slack, email, etc.)
    - name: 'critical'
      # Critical alerts
    - name: 'warning'
      # Warning alerts

# Node Exporter
nodeExporter:
  enabled: true

# Kube State Metrics
kubeStateMetrics:
  enabled: true

# CoreDNS monitoring
coreDns:
  enabled: true

# Kube API Server monitoring
kubeApiServer:
  enabled: true

# Kube Controller Manager
kubeControllerManager:
  enabled: true

# Kube Scheduler
kubeScheduler:
  enabled: true

# Kube Proxy
kubeProxy:
  enabled: true

# Kubelet monitoring
kubelet:
  enabled: true
  serviceMonitor:
    cAdvisor: true
EOF

echo "✓ Custom values file created"

# 4. Install kube-prometheus-stack
echo ""
echo "Installing kube-prometheus-stack (this may take 2-3 minutes)..."
helm install $RELEASE_NAME prometheus-community/kube-prometheus-stack \
  --namespace $NAMESPACE \
  --values /tmp/prometheus-values.yaml \
  --wait

echo "✓ Kube-prometheus-stack installed"

# 5. Wait for all pods to be ready
echo ""
echo "Waiting for all monitoring pods to be ready..."
kubectl wait --for=condition=ready pod --all -n $NAMESPACE --timeout=300s

echo "✓ All pods are ready"

# 6. Get service information
echo ""
echo "========================================"
echo "Getting Service Information"
echo "========================================"
echo ""

GRAFANA_LB=$(kubectl get svc -n $NAMESPACE $RELEASE_NAME-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
PROMETHEUS_PORT=$(kubectl get svc -n $NAMESPACE $RELEASE_NAME-kube-prom-prometheus -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "9090")

echo "✓ Services deployed successfully!"
echo ""
echo "Access Information:"
echo "==================="
echo ""
echo "Grafana:"
if [ "$GRAFANA_LB" != "pending" ]; then
    echo "  URL: http://$GRAFANA_LB"
else
    echo "  LoadBalancer is being created. Check status with:"
    echo "  kubectl get svc -n $NAMESPACE $RELEASE_NAME-grafana"
    echo ""
    echo "  Or use port-forward:"
    echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-grafana 3000:80"
    echo "  Then access: http://localhost:3000"
fi
echo "  Username: admin"
echo "  Password: admin123"
echo ""
echo "Prometheus:"
echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-kube-prom-prometheus 9090:9090"
echo "  Then access: http://localhost:9090"
echo ""
echo "Alertmanager:"
echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-kube-prom-alertmanager 9093:9093"
echo "  Then access: http://localhost:9093"
echo ""

# 7. Create ServiceMonitor for BookStore application
echo "Creating ServiceMonitor for BookStore application..."
cat > /tmp/bookstore-servicemonitor.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: bookapp-api-metrics
  namespace: bookstore
  labels:
    app: bookapp-api
    release: kube-prometheus-stack
spec:
  type: ClusterIP
  ports:
  - name: metrics
    port: 9090
    targetPort: 3000
    protocol: TCP
  selector:
    app: bookapp-api
---
apiVersion: v1
kind: Service
metadata:
  name: bookapp-ui-metrics
  namespace: bookstore
  labels:
    app: bookapp-ui
    release: kube-prometheus-stack
spec:
  type: ClusterIP
  ports:
  - name: metrics
    port: 9090
    targetPort: 80
    protocol: TCP
  selector:
    app: bookapp-ui
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: bookapp-api-monitor
  namespace: bookstore
  labels:
    app: bookapp-api
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: bookapp-api
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: bookapp-ui-monitor
  namespace: bookstore
  labels:
    app: bookapp-ui
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: bookapp-ui
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
EOF

kubectl apply -f /tmp/bookstore-servicemonitor.yaml
echo "✓ ServiceMonitor created"

# 8. Create PrometheusRule for alerts
echo ""
echo "Creating PrometheusRules for BookStore alerts..."
cat > /tmp/bookstore-alerts.yaml << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: bookstore-alerts
  namespace: bookstore
  labels:
    release: kube-prometheus-stack
spec:
  groups:
  - name: bookstore.rules
    interval: 30s
    rules:
    # High CPU usage
    - alert: BookStoreHighCPU
      expr: |
        sum(rate(container_cpu_usage_seconds_total{namespace="bookstore"}[5m])) by (pod) > 0.8
      for: 5m
      labels:
        severity: warning
        component: bookstore
      annotations:
        summary: "High CPU usage detected"
        description: "Pod {{ $labels.pod }} is using more than 80% CPU for 5 minutes"
    
    # High Memory usage
    - alert: BookStoreHighMemory
      expr: |
        sum(container_memory_working_set_bytes{namespace="bookstore"}) by (pod) / 
        sum(container_spec_memory_limit_bytes{namespace="bookstore"}) by (pod) > 0.85
      for: 5m
      labels:
        severity: warning
        component: bookstore
      annotations:
        summary: "High memory usage detected"
        description: "Pod {{ $labels.pod }} is using more than 85% of its memory limit"
    
    # Pod restart rate
    - alert: BookStorePodRestartingOften
      expr: |
        rate(kube_pod_container_status_restarts_total{namespace="bookstore"}[15m]) > 0
      for: 5m
      labels:
        severity: critical
        component: bookstore
      annotations:
        summary: "Pod is restarting frequently"
        description: "Pod {{ $labels.pod }} has restarted {{ $value }} times in the last 15 minutes"
    
    # Pod not ready
    - alert: BookStorePodNotReady
      expr: |
        kube_pod_status_ready{namespace="bookstore", condition="false"} == 1
      for: 10m
      labels:
        severity: critical
        component: bookstore
      annotations:
        summary: "Pod is not ready"
        description: "Pod {{ $labels.pod }} has been in a non-ready state for 10 minutes"
    
    # API availability
    - alert: BookStoreAPIDown
      expr: |
        up{job="bookstore-api"} == 0
      for: 2m
      labels:
        severity: critical
        component: bookstore-api
      annotations:
        summary: "BookStore API is down"
        description: "The BookStore API has been unreachable for 2 minutes"
    
    # UI availability
    - alert: BookStoreUIDown
      expr: |
        up{job="bookstore-ui"} == 0
      for: 2m
      labels:
        severity: critical
        component: bookstore-ui
      annotations:
        summary: "BookStore UI is down"
        description: "The BookStore UI has been unreachable for 2 minutes"
    
    # Low replica count
    - alert: BookStoreLowReplicaCount
      expr: |
        kube_deployment_status_replicas_available{namespace="bookstore"} < 
        kube_deployment_spec_replicas{namespace="bookstore"} * 0.5
      for: 5m
      labels:
        severity: warning
        component: bookstore
      annotations:
        summary: "Low replica count"
        description: "Deployment {{ $labels.deployment }} has less than 50% of desired replicas available"
EOF

kubectl apply -f /tmp/bookstore-alerts.yaml
echo "✓ PrometheusRules created"

# 9. Create custom Grafana dashboards
echo ""
echo "Creating custom Grafana dashboard ConfigMap..."
cat > /tmp/bookstore-dashboard.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: bookstore-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  bookstore-dashboard.json: |
    {
      "dashboard": {
        "title": "BookStore Application Dashboard",
        "tags": ["bookstore", "application"],
        "timezone": "browser",
        "panels": [
          {
            "title": "Pod CPU Usage",
            "type": "graph",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
            "targets": [
              {
                "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"bookstore\"}[5m])) by (pod)",
                "legendFormat": "{{pod}}"
              }
            ]
          },
          {
            "title": "Pod Memory Usage",
            "type": "graph",
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
            "targets": [
              {
                "expr": "sum(container_memory_working_set_bytes{namespace=\"bookstore\"}) by (pod)",
                "legendFormat": "{{pod}}"
              }
            ]
          },
          {
            "title": "Pod Restart Count",
            "type": "graph",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
            "targets": [
              {
                "expr": "sum(kube_pod_container_status_restarts_total{namespace=\"bookstore\"}) by (pod)",
                "legendFormat": "{{pod}}"
              }
            ]
          },
          {
            "title": "Deployment Replicas",
            "type": "stat",
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
            "targets": [
              {
                "expr": "kube_deployment_status_replicas_available{namespace=\"bookstore\"}",
                "legendFormat": "{{deployment}} - Available"
              }
            ]
          }
        ]
      }
    }
EOF

kubectl apply -f /tmp/bookstore-dashboard.yaml
echo "✓ Custom dashboard created"

# Clean up temporary files
rm -f /tmp/prometheus-values.yaml
rm -f /tmp/bookstore-servicemonitor.yaml
rm -f /tmp/bookstore-alerts.yaml
rm -f /tmp/bookstore-dashboard.yaml

echo ""
echo "========================================"
echo "✓ Monitoring Setup Complete!"
echo "========================================"
echo ""
echo "Next Steps:"
echo "1. Access Grafana and explore the dashboards"
echo "2. Import additional dashboards from grafana.com"
echo "3. Configure Alertmanager notifications (Slack, email, etc.)"
echo "4. Customize alerts in PrometheusRules"
echo ""
echo "Useful Commands:"
echo "  # View all monitoring resources"
echo "  kubectl get all -n monitoring"
echo ""
echo "  # Check Prometheus targets"
echo "  kubectl port-forward -n monitoring svc/$RELEASE_NAME-kube-prom-prometheus 9090:9090"
echo ""
echo "  # View Grafana dashboards"
echo "  kubectl port-forward -n monitoring svc/$RELEASE_NAME-grafana 3000:80"
echo ""
echo "  # Check alerts"
echo "  kubectl get prometheusrules -n bookstore"
echo ""
echo "  # View ServiceMonitors"
echo "  kubectl get servicemonitors -n bookstore"
echo ""