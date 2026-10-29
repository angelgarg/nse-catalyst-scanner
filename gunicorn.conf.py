# Loaded automatically by gunicorn from the working directory (Render runs `gunicorn flask_app:app`).
# One worker keeps the in-memory CDN/analysis cache shared and fits Render free (512 MB).
workers = 1
threads = 8
timeout = 120
