import os
import time

from flask import Flask, jsonify

app = Flask(__name__)

START_TIME = time.time()


@app.after_request
def set_security_headers(response):
    """Attach secure response headers on every reply (GCC control: secure headers)."""
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Cache-Control"] = "no-store"
    response.headers["Content-Security-Policy"] = "default-src 'none'"
    return response


@app.route("/")
def index():
    return jsonify({
        "service": "NTT GCC Sample API",
        "version": os.getenv("APP_VERSION", "1.0.0"),
        "environment": os.getenv("APP_ENV", "production"),
        "uptime_seconds": int(time.time() - START_TIME),
    })


@app.route("/healthz")
def health():
    """ALB target group health check — must return HTTP 200."""
    return jsonify({
        "status": "healthy",
        "uptime_seconds": int(time.time() - START_TIME),
    }), 200


@app.route("/api/status")
def status():
    return jsonify({
        "status": "ok",
        "region": os.getenv("AWS_DEFAULT_REGION", "unknown"),
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
    
