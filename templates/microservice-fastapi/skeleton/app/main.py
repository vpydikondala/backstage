from fastapi import FastAPI

app = FastAPI(title="{{ name }}")

@app.get("/")
def root():
    return {"service": "{{ name }}", "status": "ok"}

@app.get("/health")
def health():
    return {"ok": True}
