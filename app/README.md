# Application Folder

This folder owns the source code, packaging config, and runtime dependencies for the FastAPI microservice application. It implements the endpoint logic for client requests, exposes metrics endpoints for Prometheus scraping, and declares base container execution environments.

## Architecture

```
+---------------------------------------------+
|                app/ Folder                  |
|                                             |
|  +---------------------------------------+  |
|  |                main.py                |  |
|  +---------------------------------------+  |
|      |                        |             |
|      v                        v             |
|  [requirements.txt]      [Dockerfile]       |
+---------------------------------------------+
```

| File Name | Upstream Dependency | Downstream Target |
|:---|:---|:---|
| `main.py` | `requirements.txt` | `Dockerfile` |
| `Dockerfile` | `main.py` | `k8s/fastapi/templates/deployment.yaml` |
| `requirements.txt` | None | `main.py` |

## File-by-file explanation

### main.py

The `app = FastAPI(title="Hello World API", version="1.0.0")` declaration instantiates the core web application context. Specifying a descriptive title and version configures the metadata shown on the OpenAPI interactive documentation page.

The `Instrumentator().instrument(app).expose(app)` call configures the application to collect HTTP request metrics and publish them on the `/metrics` endpoint. This is required by Prometheus to query metrics. If missing, metrics-based autoscaling using KEDA will fail.

The `class RootResponse(BaseModel)` model defines the response payload schema for the root route. It ensures that output types are checked and validated before delivery.
The `message: str` field specifies the greeting string returned to clients.
The `version: str` field holds the metadata tracking the current application version tag.
The `node: str` field holds the name of the Kubernetes worker node hosting this container. It retrieves this from the `NODE_NAME` environment variable, which is populated from the Downward API inside `k8s/fastapi/templates/deployment.yaml`.
The `pod: str` field holds the name of the running Kubernetes pod. It retrieves this from the `POD_NAME` environment variable, populated from the Downward API inside `k8s/fastapi/templates/deployment.yaml`.
The `zone: str` field holds the AWS Availability Zone where the pod runs. It retrieves this from the `ZONE` environment variable, populated by the Helm template loop inside `k8s/fastapi/templates/deployment.yaml`. If any of these environment variables are missing or misconfigured, the responses returned to clients will have empty or unknown markers.

The `class HealthResponse(BaseModel)` model defines the schema returned on readiness and liveness queries.
The `status: str` field exposes the status state, returning a value of `healthy`.

The `@app.get("/", response_model=RootResponse)` route accepts requests on root and returns the system metadata payload. It maps to the target path configured inside `k8s/fastapi/templates/httproute.yaml`.

The `@app.get("/health", response_model=HealthResponse)` route accepts request checks on path `/health`. It maps to liveness and readiness probe checks configured inside `k8s/fastapi/templates/deployment.yaml`. If this route is removed or renamed, Kubernetes will mark the containers as unhealthy and restart them endlessly.

### Dockerfile

The `FROM python:3.12-slim` argument specifies the parent container image context. Using a slim variant keeps image sizes small and minimizes vulnerable packages.

The `WORKDIR /app` command sets the working directory context for all subsequent build steps.

The `COPY requirements.txt .` line copies dependency declarations into the image before source files to optimize Docker build layer caching.

The `RUN pip install --no-cache-dir -r requirements.txt` line installs libraries without caching build layers, keeping container footprints minimal.

The `COPY main.py .` line copies the FastAPI implementation script into the image.

The `RUN adduser --disabled-password --gecos "" appuser` line creates a dedicated system user account.

The `USER appuser` command switches container execution context away from root to `appuser`. Running as root violates Kubernetes security policies and will fail in restricted namespaces.

The `EXPOSE 8000` declaration states the container is configured to receive connections on port 8000. It must match the port targets configured inside `k8s/fastapi/templates/deployment.yaml`.

The `CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]` command runs the ASGI server when starting the container. Binding to host `0.0.0.0` is required to allow incoming network traffic.

### requirements.txt

The `fastapi==0.136.3` pin specifies the FastAPI version used for routing. If missing, container builds fail on package lookup.

The `uvicorn[standard]==0.49.0` pin installs the server daemon used to process connections.

The `prometheus-fastapi-instrumentator==7.1.0` pin exposes metrics.

## Versions and APIs used

| Tool | Version | Purpose |
|:---|:---|:---|
| Python | 3.12-slim | Container runtime environment |
| FastAPI | 0.136.3 | Web routing framework |
| Uvicorn | 0.49.0 | Application server |
| Prometheus Instrumentator | 7.1.0 | Metrics collection |

## Prerequisites

| Dependency | Required State | Folder |
|:---|:---|:---|
| Docker | Running daemon to package image | None |
| Python | Runtime installed for local testing | None |

## Commands

We initialize the local environment to install the runtime dependencies.
```bash
pip install -r app/requirements.txt
```

We launch the ASGI server locally to test endpoints outside of Docker.
```bash
uvicorn app.main:app --host 127.0.0.1 --port 8000
```

We compile the Docker container image locally to verify the build configuration.
```bash
docker build -t fastapi-app:latest ./app
```

We run the compiled image locally to verify runtime execution parameters.
```bash
docker run -p 8000:8000 fastapi-app:latest
```

## Troubleshooting

We resolve connection errors by verifying that the Uvicorn server is bound to `0.0.0.0` inside the container context, as binding to `127.0.0.1` will reject external requests.

We fix startup crashes with missing modules by verifying that the requirements list includes all required import packages and rebuild the container.

We resolve permissions issues inside Kubernetes by verifying that no files require root access, since the container runtime is restricted to execute as the non-root system user `appuser`.

## References

| Tool | Official Documentation |
|:---|:---|
| FastAPI | [FastAPI Docs](https://fastapi.tiangolo.com/) |
| Uvicorn | [Uvicorn Docs](https://www.uvicorn.org/) |
| Docker | [Docker Docs](https://docs.docker.com/) |
