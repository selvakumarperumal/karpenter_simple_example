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

### deployment.yaml

The `{{- range $zoneSuffix := .Values.zones }}` statement iterates over availability zones defined in [values.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/fastapi/values.yaml#L2) to render zone-specific Deployments.

The `apiVersion: apps/v1` and `kind: Deployment` fields target the core Kubernetes workloads API schema.

The `metadata.name: fastapi-app-zone-{{ $zoneSuffix }}` field dynamically names the resource instance (e.g. `fastapi-app-zone-a`).

The `spec.replicas: 1` field configures initial replicas. This is managed dynamically at runtime by KEDA.

The `spec.selector.matchLabels.app: fastapi-app` and `zone: {{ $zoneName }}` fields identify pods managed by this deployment.

The `spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms` block declares hard scheduling affinity constraints.
The `topology.kubernetes.io/zone` matcher uses the `In` operator with `$zoneName` (e.g. `ap-south-1a`) to force pods to run only on nodes located in the matching Availability Zone, preventing cross-zone scheduling.

The `spec.template.spec.topologySpreadConstraints` block distributes pods.
The `topologyKey: kubernetes.io/hostname` configuration forces spreading pods across different physical nodes inside the target zone to prevent single node failures.
The `whenUnsatisfiable: ScheduleAnyway` setting prevents scheduling blocks if only one node is available.

The `spec.template.spec.containers` section configures container execution parameters.
The `image: "{{ $.Values.image.repository }}:{{ $.Values.image.tag }}"` field specifies the ECR container image location (matches `ecr_repository_url` inside [outputs.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/outputs.tf#L63)).
The `imagePullPolicy: {{ $.Values.image.pullPolicy }}` field configures image pull policies.
The `ports.containerPort: 8000` field configures port 8000 (matches port exposed in [Dockerfile](file:///home/selva/Documents/k8s/karpenter_simple_example/app/Dockerfile#L14)).
The `env` block defines environment variables.
The `POD_NAME` and `NODE_NAME` variables retrieve pod name and worker node name metadata using Downward API configurations.
The `ZONE` variable injects availability zone name. Used in [main.py](file:///home/selva/Documents/k8s/karpenter_simple_example/app/main.py#L40) to configure metadata.
The `GOOGLE_API_KEY` variable injects the key from secret `google-api-key`. If wrong, application startup checking fails.
The `resources` block configures CPU and memory requests and limits (matches parameters inside [values.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/fastapi/values.yaml#L9-L12)).
The `readinessProbe` and `livenessProbe` blocks configure health checking paths on GET `/health` on port `8000`.

### gateway.yaml

The `apiVersion: gateway.networking.k8s.io/v1` and `kind: Gateway` fields declare a Gateway API Gateway resource.

The `metadata.annotations.networking.istio.io/service-type: LoadBalancer` annotation tells Istio's auto-provisioner to create an AWS Network Load Balancer (NLB) in the public subnets tagged `kubernetes.io/role/elb = 1` inside [vpc.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/vpc.tf#L50).

The `spec.gatewayClassName: istio` field triggers Envoy proxy provisioning.

The `spec.listeners` block declares exposed endpoints.
The `port: 80` and `protocol: HTTP` fields expose port 80 for HTTP routing.
The `allowedRoutes.namespaces.from: Same` configuration restricts path routing configurations to the same namespace.

### httproute.yaml

The `apiVersion: gateway.networking.k8s.io/v1` and `kind: HTTPRoute` fields declare routing rules.

The `spec.parentRefs` block binds the route configuration.
The `name: fastapi-gateway` field targets the gateway resource.

The `spec.hostnames: ["fastapi.example.com"]` array restricts routing to requests with matching host headers.

The `spec.rules` list configures matches.
The `matches.path.type: PathPrefix` and `value: /` configurations target root path.
The `backendRefs.name: fastapi-app` and `port: 80` settings target the backend service.

### istio-destinationrule.yaml

The `apiVersion: networking.istio.io/v1` and `kind: DestinationRule` fields configure policies.

The `spec.host: fastapi-app.fastapi.svc.cluster.local` field targets the aggregate Kubernetes Service.

The `spec.trafficPolicy.loadBalancer.localityLbSetting` block configures routing.
The `enabled: true` and `distribute` variables specify routing weights (splits weights `90/5/5` to prefer local zones), avoiding cross-AZ AWS network transit fees.

The `spec.trafficPolicy.outlierDetection` block configures passive health checking.
The `consecutive5xxErrors: 3`, `interval: 10s`, `baseEjectionTime: 30s`, and `maxEjectionPercent: 50` fields define circuit breaker ejection rules.

### scaledobject.yaml

The `{{- range $zoneSuffix := .Values.zones }}` statement iterates over availability zones to render zone-specific ScaledObjects.

The `apiVersion: keda.sh/v1alpha1` and `kind: ScaledObject` fields declare scaling parameters.

The `spec.scaleTargetRef.name: fastapi-app-zone-{{ $zoneSuffix }}` field binds scaling parameters to target zone deployments.

The `spec.minReplicaCount: {{ $.Values.keda.minReplicas }}` and `maxReplicaCount: {{ $.Values.keda.maxReplicas }}` fields set pod boundary constraints.

The `spec.triggers` list declares metric scrapers.
The `type: prometheus` field specifies Prometheus metrics queries.
The `serverAddress` field points to Prometheus server URL.
The `query` field specifies PromQL rate check on `http_requests_total`.
The `threshold` parameter defines requests rate threshold per pod.

The `spec.advanced.horizontalPodAutoscalerConfig.behavior` block overrides scaling speeds.

### service.yaml

The `apiVersion: v1` and `kind: Service` fields declare access points.

The `spec.selector.app: fastapi-app` maps the service to target zone pods.

The `spec.ports.port: 80` and `targetPort: 8000` fields configure port routing.

### namespace.yaml

The `apiVersion: v1` and `kind: Namespace` fields declare the namespace boundary.

The `metadata.labels.istio-injection: enabled` label tells Istiod to automatically inject Envoy sidecars into pods deployed inside the namespace.

### podmonitor.yaml

The `apiVersion: monitoring.coreos.com/v1` and `kind: PodMonitor` fields configure scraper endpoints.

The `spec.selector.matchLabels.app: fastapi-app` targets pods.

The `spec.podMetricsEndpoints` block routes Prometheus to scrape `/metrics` on target port `http` every `15s`.

### grafana-dashboard-fastapi-overview.yaml

The `apiVersion: v1` and `kind: ConfigMap` fields target the core ConfigMap schema.

The `metadata.labels.grafana_dashboard: "1"` label tells Grafana's sidecar to import the dashboard.

The `metadata.annotations.grafana_folder: "FastAPI"` annotation groups this dashboard under a FastAPI folder.

The `data` section contains the dashboard JSON model.

### grafana-dashboard-fastapi-scaling.yaml

The `apiVersion: v1` and `kind: ConfigMap` fields target the core ConfigMap schema.

The `metadata.labels.grafana_dashboard: "1"` label tells Grafana's sidecar to import the dashboard.

The `metadata.annotations.grafana_folder: "FastAPI"` annotation groups this dashboard under a FastAPI folder.

The `data` section contains the dashboard JSON model.

## Versions and APIs used

| Component | target Version | apiVersion Group |
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
