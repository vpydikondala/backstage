from fastapi import FastAPI

app = FastAPI(title="{{ name }}")

@app.get("/")
def root():
    return {"service": "{{ name }}", "status": "ok"}
