from fastapi import FastAPI
import os

app = FastAPI(title="Hello World API", version="1.0.0")


@app.get("/")
def root():
    return {
        "message": "Hello from FastAPI on EKS with Karpenter!",
        "version": "1.0.0",
        "node": os.getenv("NODE_NAME", "unknown"),
        "pod": os.getenv("POD_NAME", "unknown"),
    }


@app.get("/health")
def health():
    return {"status": "healthy"}
