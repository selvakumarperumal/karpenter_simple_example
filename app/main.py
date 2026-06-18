from fastapi import FastAPI
from pydantic import BaseModel, Field
from prometheus_fastapi_instrumentator import Instrumentator
import os

app = FastAPI(title="Hello World API", version="1.0.0")

Instrumentator().instrument(app).expose(app)


class RootResponse(BaseModel):
    """Pydantic model describing the root API response data structure."""
    message: str = Field(description="Greeting message from the FastAPI application")
    version: str = Field(description="The application version tag")
    node: str = Field(description="The name of the Kubernetes worker node hosting this container")
    pod: str = Field(description="The name of the Kubernetes pod serving the request")
    zone: str = Field(description="The AWS Availability Zone where the pod is running")


class HealthResponse(BaseModel):
    """Pydantic model describing the health check API response status."""
    status: str = Field(description="The status of the application, typically 'healthy'")


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


@app.get("/health", response_model=HealthResponse)
def health():
    """
    Simple health check endpoint used by Kubernetes liveness and readiness probes
    to verify that the application is running and healthy.
    """
    return {"status": "healthy"}

