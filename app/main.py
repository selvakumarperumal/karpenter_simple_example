from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator
import os

app = FastAPI(title="Hello World API", version="1.0.0")

# Expose Prometheus metrics at GET /metrics.
# prometheus-fastapi-instrumentator auto-instruments every route and records:
#   http_requests_total{handler, method, status_code} — used by KEDA ScaledObjects
#   http_request_duration_seconds — latency histogram
Instrumentator().instrument(app).expose(app)


@app.get("/")
def root():
    return {
        "message": "Hello from FastAPI on EKS with Karpenter!",
        "version": "1.0.0",
        "node": os.getenv("NODE_NAME", "unknown"),
        "pod": os.getenv("POD_NAME", "unknown"),
        "zone": os.getenv("ZONE", "unknown"),
    }


@app.get("/health")
def health():
    return {"status": "healthy"}
