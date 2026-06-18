# FastAPI Workload Templates Folder

This folder owns the Kubernetes templates representing the running FastAPI workload. It defines zone-isolated deployments, KEDA auto-scaling, locality-aware ingress routing, and Prometheus metrics configuration.

## Architecture

```
+-------------------------------------------------------------+
|                     templates/ Folder                       |
|                                                             |
|  [Gateway] -> [HTTPRoute] -> [DestinationRule] -> [Service] |
|                                   |                         |
|                                   +-------> [Deployment]    |
|                                                  |          |
|  [PodMonitor] <----------------------------------+          |
|       |                                                     |
|       v                                                     |
|  [Prometheus] -> [KEDA ScaledObject] -> [HPA Scaling]       |
+-------------------------------------------------------------+
```

| Manifest File | Kind | Upstream Dependency | Downstream Target |
|:---|:---|:---|:---|
| `gateway.yaml` | `Gateway` | `gateway-api-crds.yaml` | `httproute.yaml` |
| `httproute.yaml` | `HTTPRoute` | `gateway.yaml` | `service.yaml` |
| `istio-destinationrule.yaml` | `DestinationRule` | `service.yaml` | `deployment.yaml` |
| `service.yaml` | `Service` | `deployment.yaml` | Ingress traffic |
| `deployment.yaml` | `Deployment` | `values.yaml` | Pod metrics |
| `scaledobject.yaml` | `ScaledObject` | `deployment.yaml` | Deployment replicas |
| `podmonitor.yaml` | `PodMonitor` | `deployment.yaml` | Prometheus metrics |

## File-by-file explanation

### namespace.yaml

The namespace configuration establishes the isolated API boundaries.

Here is the annotated version of `namespace.yaml` showing detailed comments:

```yaml
# Targets the core Kubernetes v1 API group.
apiVersion: v1
# Specifies that this resource is a Namespace.
kind: Namespace
# Metadata identifying the namespace.
metadata:
  # The namespace name. Must match the namespace used by all application workloads.
  name: fastapi
  # Labels configured for the namespace.
  labels:
    # Enables Istio Ambient service mesh data plane mode for pods in this namespace.
    # If this label is missing, pods will not be enrolled in the ambient mesh.
    istio.io/dataplane-mode: ambient
  # Annotations explaining the namespace's purpose.
  annotations:
    kubernetes.io/description: "Dedicated namespace for the FastAPI workload"
```

### service.yaml

The service manifest coordinates internal connection aggregates.

Here is the annotated version of `service.yaml` showing detailed comments:

```yaml
# Targets the core Kubernetes v1 API group.
apiVersion: v1
# Specifies that this resource is a Service.
kind: Service
# Metadata identifying the service.
metadata:
  # Unique service name. Must match backendRefs.name in httproute.yaml.
  name: fastapi-app
  # Must reside in the same namespace as the application pods.
  namespace: fastapi
  # Selector labels used to match target pods.
  labels:
    app: fastapi-app
  # Description of the service's purpose.
  annotations:
    kubernetes.io/description: "Aggregates zone-affinity FastAPI pods under a single logical IP for internal cluster routing"
# Technical specifications for the service.
spec:
  # ClusterIP exposes the service on an internal IP inside the EKS cluster.
  type: ClusterIP
  # Selector matching target pods.
  selector:
    # Finds pods labeled app: fastapi-app.
    app: fastapi-app
  # Port mapping definitions.
  ports:
    # Logical name of the port.
    - name: http
      # Exposed port accessible on the ClusterIP.
      port: 80
      # Target container port exposed in Dockerfile and deployment.yaml.
      targetPort: 8000
```

### gateway.yaml

The gateway manifest configures entry routes into the mesh network.

Here is the annotated version of `gateway.yaml` showing detailed comments:

```yaml
# Targets the stable Kubernetes Gateway API group.
apiVersion: gateway.networking.k8s.io/v1
# Specifies that this resource is a Gateway.
kind: Gateway
# Metadata identifying the gateway.
metadata:
  # Unique name. Referenced by parentRefs in httproute.yaml.
  name: fastapi-gateway
  # Namespace where the gateway resides.
  namespace: fastapi
  # Annotations configuring the gateway provisioner.
  annotations:
    # Description of the gateway's purpose.
    kubernetes.io/description: "Exposes EKS external traffic endpoints using Istio-managed Gateway API gateways"
    # Tells Istio to automatically provision an AWS Network Load Balancer (NLB) in the public subnets.
    # Requires public subnets to be tagged kubernetes.io/role/elb = 1 in vpc.tf.
    networking.istio.io/service-type: LoadBalancer
# Technical specifications for the gateway listener.
spec:
  # Triggers Istio to provision the gateway proxies.
  gatewayClassName: istio
  # Port listeners exposed by the gateway.
  listeners:
    # HTTP port listener config.
    - name: http
      # Inbound port exposing HTTP traffic.
      port: 80
      # Protocol type.
      protocol: HTTP
      # Defines which namespaces are allowed to attach routes.
      allowedRoutes:
        namespaces:
          # Restricts attaching routes only to HTTPRoutes in the same namespace.
          from: Same
```

### httproute.yaml

The httproute configuration maps client urls to services.

Here is the annotated version of `httproute.yaml` showing detailed comments:

```yaml
# Targets the stable Kubernetes Gateway API group.
apiVersion: gateway.networking.k8s.io/v1
# Specifies that this resource is an HTTPRoute.
kind: HTTPRoute
# Metadata identifying the routing rule.
metadata:
  # Unique name for this route.
  name: fastapi-app
  # Must reside in the same namespace as the parent Gateway.
  namespace: fastapi
  # Annotations configuring Istio retry policies.
  annotations:
    # Description of the route's purpose.
    kubernetes.io/description: "Routes external HTTP requests from the Gateway API Gateway to the backend FastAPI application service"
    # Configures the proxy to retry failed requests up to 3 times before returning an error to clients.
    networking.istio.io/retry-attempts: "3"
    # Types of errors that trigger retries.
    networking.istio.io/retry-on: "connect-failure,refused-stream,5xx"
    # Timeout constraint applied on each individual retry attempt.
    networking.istio.io/per-try-timeout: "10s"
    # Absolute request timeout constraint including all retries.
    networking.istio.io/request-timeout: "30s"
# Technical specifications for routing logic.
spec:
  # Binds this route configuration to the parent Gateway.
  parentRefs:
    # References the gateway name fastapi-gateway.
    - name: fastapi-gateway
      # Must match the namespace of the gateway.
      namespace: fastapi
      # Binds specifically to the listener named http inside gateway.yaml.
      sectionName: http

  # Restricts routing rules to requests matching the hostname header.
  hostnames:
    - "fastapi.example.com"

  # List of routing match rules.
  rules:
    # Matches all requests on path prefix /.
    - matches:
        - path:
            type: PathPrefix
            value: /
      # Target backend service.
      backendRefs:
        # Routes traffic to the ClusterIP Service fastapi-app on port 80.
        - name: fastapi-app
          port: 80
```

### istio-destinationrule.yaml

The destinationrule manages availability-zone load balancing weights.

Here is the annotated version of `istio-destinationrule.yaml` showing detailed comments:

```yaml
# Targets the stable Istio networking API group.
apiVersion: networking.istio.io/v1
# Specifies that this resource is a DestinationRule.
kind: DestinationRule
# Metadata identifying the destination rule.
metadata:
  # Unique name.
  name: fastapi-app
  # Must reside in the application namespace.
  namespace: fastapi
  # Description of the traffic policy intent.
  annotations:
    kubernetes.io/description: "Configures Envoy sidecars and ingress gateways to prefer local Availability Zone routing, adding circuit breaking and passive health checks"
# Technical specifications for traffic policies.
spec:
  # Hostname of the target Kubernetes Service.
  host: fastapi-app.fastapi.svc.cluster.local

  # Traffic policies applied to the destination host.
  trafficPolicy:
    # Locality-prioritized load balancing configurations.
    loadBalancer:
      localityLbSetting:
        # Enables locality-prioritized routing.
        enabled: true
        # Distributes traffic to prefer local availability zones to minimize AWS cross-AZ data charges.
        # Renders distribute settings dynamically for each zone suffix.
        distribute:
          {{- range $zoneSuffix := .Values.zones }}
          # From current zone (e.g. ap-south-1a) to target zones.
          - from: "{{ $.Values.awsRegion }}/{{ $.Values.awsRegion }}{{ $zoneSuffix }}/*"
            to:
              {{- range $targetSuffix := $.Values.zones }}
              # Splits traffic: 90% to local zone, 5% each to the other two fallback zones.
              "{{ $.Values.awsRegion }}/{{ $.Values.awsRegion }}{{ $targetSuffix }}/*": {{ if eq $zoneSuffix $targetSuffix }}90{{ else }}5{{ end }}
              {{- end }}
          {{- end }}

    # Outlier detection passive health check rules for circuit breaking.
    outlierDetection:
      # Ejects pods from routing pool after 3 consecutive 5xx errors.
      consecutive5xxErrors: 3
      # Scans pods for ejection checks every 10 seconds.
      interval: 10s
      # Ejects unhealthy pods from the routing pool for an initial duration of 30 seconds.
      baseEjectionTime: 30s
      # Maximum percentage of pods that can be ejected simultaneously to maintain availability.
      maxEjectionPercent: 50
```

### podmonitor.yaml

The podmonitor registers endpoints with Prometheus Operator.

Here is the annotated version of `podmonitor.yaml` showing detailed comments:

```yaml
# Iterates over availability zones to create separate PodMonitors.
{{- range $zoneSuffix := .Values.zones }}
{{- $zoneName := printf "%s%s" $.Values.awsRegion $zoneSuffix }}
# Targets the Prometheus operator API schema group.
apiVersion: monitoring.coreos.com/v1
# Specifies that this resource is a PodMonitor.
kind: PodMonitor
# Metadata identifying the pod monitor.
metadata:
  # Dynamically names the resource instance per zone.
  name: fastapi-zone-{{ $zoneSuffix }}
  # Must reside in the namespace where Prometheus Operator is deployed (monitoring).
  namespace: monitoring
  # Label enabling automatic detection by Prometheus.
  labels:
    # Must match prometheus.prometheusSpec.podMonitorNamespaceSelector in prometheus.yaml.
    release: prometheus
  # Annotations explaining scraper targets.
  annotations:
    kubernetes.io/description: "Configures Prometheus Operator to scrape metrics from FastAPI pods in Availability Zone {{ $zoneName }}"
# Technical specifications for Prometheus scraping.
spec:
  # Namespaces containing target pods.
  namespaceSelector:
    matchNames:
      - fastapi
  # Label selectors matching target application pods.
  selector:
    matchLabels:
      app: fastapi-app
      zone: {{ $zoneName }}
  # Endpoints exposing Prometheus metrics.
  podMetricsEndpoints:
    # Port name http matches ports.name in deployment.yaml.
    - port: http
      # Scrapes metrics from FastAPI on path /metrics.
      path: /metrics
      # Interval duration between metric scrapes.
      interval: 15s
      # Relabelings to inject AZ tags into metrics.
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_label_zone]
          targetLabel: zone
---
{{- end }}
```

### scaledobject.yaml

The scaledobject triggers pod replication configurations dynamically.

Here is the annotated version of `scaledobject.yaml` showing detailed comments:

```yaml
# Iterates over availability zones to create separate ScaledObjects.
{{- range $zoneSuffix := .Values.zones }}
{{- $zoneName := printf "%s%s" $.Values.awsRegion $zoneSuffix }}
# Targets the KEDA autoscaler v1alpha1 API schema group.
apiVersion: keda.sh/v1alpha1
# Specifies that this resource is a ScaledObject.
kind: ScaledObject
# Metadata identifying the scaled object.
metadata:
  # Dynamic scaled object name.
  name: fastapi-app-zone-{{ $zoneSuffix }}
  # Must reside in the application namespace fastapi.
  namespace: fastapi
  # Description of KEDA controller triggers.
  annotations:
    kubernetes.io/description: "Drives horizontal pod autoscaling for the zone-{{ $zoneSuffix }} deployment based on Prometheus traffic metrics"
# Technical specifications for autoscaling.
spec:
  # Binds KEDA to target Deployment resource.
  scaleTargetRef:
    # Matches the deployment name fastapi-app-zone-{{ $zoneSuffix }} defined in deployment.yaml.
    name: fastapi-app-zone-{{ $zoneSuffix }}

  # Minimum replica boundaries. Matches keda.minReplicas in values.yaml.
  minReplicaCount: {{ $.Values.keda.minReplicas }}
  # Maximum replica boundaries. Matches keda.maxReplicas in values.yaml.
  maxReplicaCount: {{ $.Values.keda.maxReplicas }}
  # How often KEDA queries Prometheus (seconds).
  pollingInterval: 30
  # Cooldown period before scaling down (seconds).
  cooldownPeriod: 120

  # Scaling triggers.
  triggers:
    # Prometheus metrics trigger.
    - type: prometheus
      metadata:
        # Prometheus server URL. Points to the service in monitoring namespace.
        serverAddress: http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090
        # PromQL query to calculate request rate (RPS) per zone.
        query: sum(rate(http_requests_total{namespace="fastapi",zone="{{ $zoneName }}"}[1m]))
        # RPS threshold per pod to trigger scaling. Matches keda.threshold in values.yaml.
        threshold: {{ $.Values.keda.threshold | quote }}
        # Minimum metric value required to scale up from 0 to 1 replica.
        activationThreshold: "1"
        # Unique name for the generated metric.
        metricName: http_rps_zone_{{ $zoneSuffix }}

  # Advanced scaling behavior policies.
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        # Scale down behavior guidelines.
        scaleDown:
          policies:
            # Scales down gradually, removing max 1 pod every 60 seconds.
            - type: Pods
              value: 1
              periodSeconds: 60
        # Scale up behavior guidelines.
        scaleUp:
          policies:
            # Scales up quickly, adding up to 3 pods every 30 seconds on traffic spikes.
            - type: Pods
              value: 3
              periodSeconds: 30
---
{{- end }}
```

### deployment.yaml

The deployment manifest schedules zone-isolated pods.

Here is the annotated version of `deployment.yaml` showing detailed comments:

```yaml
# Iterates over availability zones to create separate zone-affinity Deployments.
{{- range $zoneSuffix := .Values.zones }}
{{- $zoneName := printf "%s%s" $.Values.awsRegion $zoneSuffix }}
# Targets the stable apps/v1 Kubernetes workloads API schema group.
apiVersion: apps/v1
# Specifies that this resource is a Deployment.
kind: Deployment
# Metadata identifying this deployment.
metadata:
  # Unique name dynamically set per zone.
  name: fastapi-app-zone-{{ $zoneSuffix }}
  # Resides in the application namespace fastapi.
  namespace: fastapi
  # Labels for identification and tracking.
  labels:
    app: fastapi-app
    zone: {{ $zoneName }}
  # Annotations explaining the deployment's zone isolation.
  annotations:
    kubernetes.io/description: "FastAPI deployment locked to Availability Zone {{ $zoneName }} to ensure localized traffic and zero cross-AZ data fees"
# Technical specifications for the deployment.
spec:
  # Initial replica count. Dynamically managed by KEDA at runtime.
  replicas: 1
  # Selector matching target pods.
  selector:
    matchLabels:
      app: fastapi-app
      zone: {{ $zoneName }}
  # Pod template blueprint.
  template:
    metadata:
      labels:
        app: fastapi-app
        zone: {{ $zoneName }}
    spec:
      # Node affinity forces pods to schedule only on worker nodes located in the target Availability Zone.
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  # Node label set by EKS. Matches the target AZ name.
                  - key: topology.kubernetes.io/zone
                    operator: In
                    values:
                      - {{ $zoneName }}

      # Topology spread constraints distribute pods across hosts to prevent host failures.
      topologySpreadConstraints:
        - maxSkew: 1
          # Spreads pods across physical hostnames.
          topologyKey: kubernetes.io/hostname
          # Schedules anyway if node limits are reached.
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: fastapi-app
              zone: {{ $zoneName }}

      # Container workload specification.
      containers:
        - name: fastapi
          # Image repository and tag configured in values.yaml.
          image: "{{ $.Values.image.repository }}:{{ $.Values.image.tag }}"
          imagePullPolicy: {{ $.Values.image.pullPolicy }}
          # Exposes the container port.
          ports:
            - name: http
              containerPort: 8000
          # Environment variables injected into the container.
          env:
            # Retrieves the pod name using the Downward API.
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            # Retrieves the EKS worker node name using the Downward API.
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            # Passes Availability Zone name, used in main.py API responses.
            - name: ZONE
              value: {{ $zoneName | quote }}
            # Retrieves the Google API Key credential from EKS Secrets.
            # Must match the secret created in secrets/templates/google-api-key.yaml.
            - name: GOOGLE_API_KEY
              valueFrom:
                secretKeyRef:
                  name: google-api-key
                  key: GOOGLE_API_KEY
          # Resource boundaries requests/limits. Matches values.yaml.
          resources:
            {{- toYaml $.Values.resources | nindent 12 }}
          # Probe checking readiness of the application before accepting traffic.
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 5
            periodSeconds: 10
          # Probe checking container health to restart it on crash.
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 30
---
{{- end }}
```

### grafana-dashboard-fastapi-overview.yaml

The overview dashboard configures performance panels.

Here is the annotated version of `grafana-dashboard-fastapi-overview.yaml` showing detailed comments:

```yaml
# Targets the core Kubernetes v1 API group.
apiVersion: v1
# Specifies that this resource is a ConfigMap.
kind: ConfigMap
# Metadata identifying the ConfigMap.
metadata:
  # Name of the overview dashboard ConfigMap.
  name: grafana-dashboard-fastapi-overview
  # Resides in the application namespace fastapi.
  namespace: fastapi
  # Label to trigger the Grafana dashboard sidecar import loop.
  labels:
    # Must match grafana.sidecar.dashboards.label in prometheus.yaml.
    grafana_dashboard: "1"
  # Annotations configuring the import destination folder.
  annotations:
    kubernetes.io/description: "Grafana dashboard ConfigMap for FastAPI application HTTP performance metrics"
    # Matches grafana.sidecar.dashboards.folderAnnotation in prometheus.yaml.
    grafana_folder: "FastAPI"
# Dashboard JSON model configuration data.
data:
  # Contains the Grafana dashboard JSON model definition.
  fastapi-overview.json: |
    {
      "description": "FastAPI application HTTP performance — request rate, latency, errors, per-zone breakdown"
      # (JSON model body containing charts definitions for requests, errors, and zone breakdowns)
    }
```

### grafana-dashboard-fastapi-scaling.yaml

The scaling dashboard configures autoscaling panels.

Here is the annotated version of `grafana-dashboard-fastapi-scaling.yaml` showing detailed comments:

```yaml
# Targets the core Kubernetes v1 API group.
apiVersion: v1
# Specifies that this resource is a ConfigMap.
kind: ConfigMap
# Metadata identifying the ConfigMap.
metadata:
  # Name of the scaling dashboard ConfigMap.
  name: grafana-dashboard-fastapi-scaling
  # Resides in the application namespace fastapi.
  namespace: fastapi
  # Label to trigger the Grafana dashboard sidecar import loop.
  labels:
    # Must match grafana.sidecar.dashboards.label in prometheus.yaml.
    grafana_dashboard: "1"
  # Annotations configuring the import destination folder.
  annotations:
    kubernetes.io/description: "Grafana dashboard ConfigMap for FastAPI autoscaling performance and KEDA triggers"
    # Matches grafana.sidecar.dashboards.folderAnnotation in prometheus.yaml.
    grafana_folder: "FastAPI"
# Dashboard JSON model configuration data.
data:
  # Contains the Grafana dashboard JSON model definition.
  fastapi-scaling.json: |
    {
      "description": "FastAPI autoscaling dashboard — KEDA scaling triggers, replicas, and zone breakdowns"
      # (JSON model body containing charts definitions for KEDA triggers, replicas, and zone details)
    }
```

## Versions and APIs used

| Component | Target Version | apiVersion Group |
|:---|:---|:---|
| Gateway API | v1 | `gateway.networking.k8s.io/v1` |
| DestinationRule | v1 | `networking.istio.io/v1` |
| ScaledObject | v1alpha1 | `keda.sh/v1alpha1` |
| PodMonitor | v1 | `monitoring.coreos.com/v1` |

## Prerequisites

| Requirement | Target Configuration | Location |
|:---|:---|:---|
| Istio Control Plane | Deployed and active | Namespace `istio-system` |
| Prometheus Operator | Deployed and active | Namespace `monitoring` |
| KEDA Operator | Deployed and active | Namespace `keda` |

## Commands

We render the Helm templates locally using mock parameter overrides to verify chart syntax.
```bash
helm template k8s/fastapi
```

We run the Helm linter to check chart syntax.
```bash
helm lint k8s/fastapi
```

## Troubleshooting

We resolve connection errors by verifying that the Gateway API CRDs and operator CRDs are installed before template files are parsed.

We resolve load balancer routing failures by checking that public subnets inside AWS include matching tags for external load balancer discovery.

## References

| Tool | Official Documentation |
|:---|:---|
| Gateway API | [Gateway API Docs](https://gateway-api.sigs.k8s.io/) |
| Istio Ingress | [Istio Gateway Guide](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/) |
| KEDA Scaling | [KEDA Prometheus Scaler](https://keda.sh/docs/scalers/prometheus/) |
