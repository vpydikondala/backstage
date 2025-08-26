import os
from fastapi import FastAPI

service_name = os.getenv("SERVICE_NAME", "Backstage Microservice")
app = FastAPI(title=service_name)

# Root endpoint
@app.get("/")
def root():
    return {"service": "{{ name }}", "status": "ok"}

# Health check endpoint for liveness/readiness probes
@app.get("/health")
def health_check():
    return {"status": "ok"}

# Optional: Add another endpoint for /status
@app.get("/status")
def status_check():
    return {"service": "{{ name }}", "status": "healthy"}

