from flask import Flask, jsonify
import os

app = Flask(__name__)

DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
SECRET_KEY = os.environ.get("SECRET_KEY", "")

@app.route("/")
def index():
    return jsonify({"status": "ok", "message": "DevSecOps Demo App"})

@app.route("/health")
def health():
    return jsonify({"status": "healthy"})

@app.route("/api/version")
def version():
    return jsonify({"version": "1.0.0", "env": os.environ.get("APP_ENV", "production")})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
