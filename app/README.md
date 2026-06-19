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

The main FastAPI application implementation script manages web routing and metric collection.

Here is the annotated version of `main.py` showing detailed comments:

```python
# Import FastAPI to create the web application instance.
from fastapi import FastAPI
# Import BaseModel and Field from pydantic to declare request/response schemas.
from pydantic import BaseModel, Field
# Import Instrumentator to expose Prometheus metrics for Karpenter/KEDA autoscaling.
from prometheus_fastapi_instrumentator import Instrumentator
# Import os to retrieve node name and pod name from EKS environment variables.
import os

# Instantiate FastAPI application context with metadata for OpenAPI docs.
app = FastAPI(title="Hello World API", version="1.0.0")

# Instrument application and expose the /metrics endpoint.
# If omitted, KEDA scaledobject.yaml metrics queries will fail.
Instrumentator().instrument(app).expose(app)


# Define API key validation response schema.
class ApiKeyResponse(BaseModel):
    """Pydantic model describing the API key validation response."""
    # The status of the API key check.
    status: str = Field(description="The status of the API key validation")


# Define root endpoint response schema to validate outgoing payloads.
class RootResponse(BaseModel):
    """Pydantic model describing the root API response data structure."""
    # Greeting message returned by the service.
    message: str = Field(description="Greeting message from the FastAPI application")
    # Application version metadata tracker.
    version: str = Field(description="The application version tag")
    # Worker node hosting the container, passed from deployment.yaml downward API.
    node: str = Field(description="The name of the Kubernetes worker node hosting this container")
    # Pod name hosting the container, passed from deployment.yaml downward API.
    pod: str = Field(description="The name of the Kubernetes pod serving the request")
    # Availability zone, passed from deployment.yaml topology settings.
    zone: str = Field(description="The AWS Availability Zone where the pod is running")


# Define health check endpoint response schema.
class HealthResponse(BaseModel):
    """Pydantic model describing the health check API response status."""
    # Service health status string.
    status: str = Field(description="The status of the application, typically 'healthy'")


# Root GET endpoint returning environment context metadata.
@app.get("/", response_model=RootResponse)
def root():
    """
    Retrieve basic information about the API, including the running pod,
    its host Kubernetes node, and the AWS Availability Zone.
    """
    return {
        "message": "Hello from FastAPI on EKS with Karpenter!",
        "version": "1.0.0",
        "node": os.getenv("NODE_NAME", "unknown"),
        "pod": os.getenv("POD_NAME", "unknown"),
        "zone": os.getenv("ZONE", "unknown"),
    }


# Health GET endpoint checked by Kubernetes liveness and readiness probes.
# If this returns an error or is deleted, Kubernetes restarts the pod endlessly.
@app.get("/health", response_model=HealthResponse)
def health():
    """
    Simple health check endpoint used by Kubernetes liveness and readiness probes
    to verify that the application is running and healthy.
    """
    return {"status": "healthy"}


# API key validation GET endpoint.
# Returns success if the key is retrieved from AWS Secrets Manager.
@app.get("/api-key", response_model=ApiKeyResponse)
def check_api_key():
    """
    Check if the GOOGLE_API_KEY environment variable is configured and active.
    """
    key = os.getenv("GOOGLE_API_KEY")
    if key:
        return {"status": "success"}
    return {"status": "missing"}
```

### Dockerfile

The container image configuration file defines the compilation and execution steps for Docker packaging.

Here is the annotated version of `Dockerfile` showing detailed comments:

```dockerfile
# Target the slim Python parent image to minimize security vulnerabilities.
FROM python:3.12-slim

# Establish /app as the execution path context for all run commands.
WORKDIR /app

# Copy dependency requirements before source files to maximize layer cache use.
COPY requirements.txt .
# Run pip install with no-cache flag to minimize final container image size.
RUN pip install --no-cache-dir -r requirements.txt

# Copy main application script into the current working directory.
COPY main.py .

# Create a non-root system user account for secure container isolation.
RUN adduser --disabled-password --gecos "" appuser
# Switch default execution context to appuser to satisfy EKS security rules.
USER appuser

# State that the container accepts incoming traffic on port 8000.
# Must match targetPort in service.yaml and containerPort in deployment.yaml.
EXPOSE 8000

# Execute ASGI web server binding to all network interfaces.
# If bound to 127.0.0.1, external traffic from gateway.yaml is blocked.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### requirements.txt

The dependency package list maps libraries to explicit versions.

Here is the annotated version of `requirements.txt` showing detailed comments:

```txt
# FastAPI routing framework pin.
fastapi==0.136.3
# Uvicorn ASGI server daemon and standard dependencies pin.
uvicorn[standard]==0.49.0
# Prometheus FastAPI instrumentator for metrics pin.
prometheus-fastapi-instrumentator==7.1.0
```

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
