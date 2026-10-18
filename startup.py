"""
Render startup helper — run once before gunicorn.
Ensures site/ directory exists and builds the dashboard if index.html is missing.
Called automatically via render.yaml buildCommand.
"""
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SITE_DIR = os.path.join(HERE, "site")
INDEX = os.path.join(SITE_DIR, "index.html")

os.makedirs(SITE_DIR, exist_ok=True)

if not os.path.exists(INDEX):
    print("[startup] index.html missing — running build_dashboard.py ...")
    result = subprocess.run(
        [sys.executable, os.path.join(HERE, "build_dashboard.py")],
        cwd=HERE
    )
    if result.returncode == 0:
        print("[startup] Build OK")
    else:
        print("[startup] Build failed — app will start but / will show an error")
else:
    print("[startup] index.html exists — skipping build")
