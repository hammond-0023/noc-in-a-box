"""Tiny stdlib HTTP service used as the monitored workload.

Endpoints
  /          -> 200 JSON hello
  /health    -> 200 while healthy (ALB health check)
  /fail      -> 500 (used later to trigger alerts on purpose)
Logs are single-line JSON so Datadog/CloudWatch can parse them.
"""
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8080"))
ENV = os.environ.get("APP_ENV", "local")
VERSION = os.environ.get("APP_VERSION", "dev")


def log(**fields):
    fields["ts"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    fields["env"] = ENV
    sys.stdout.write(json.dumps(fields) + "\n")
    sys.stdout.flush()


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body):
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        start = time.time()
        if self.path == "/health":
            status, body = 200, {"status": "ok"}
        elif self.path == "/fail":
            status, body = 500, {"status": "error", "reason": "simulated failure"}
        else:
            status, body = 200, {"service": "noc-dev", "version": VERSION}
        self._send(status, body)
        if self.path != "/health":  # keep health-check noise out of logs
            log(level="error" if status >= 500 else "info",
                path=self.path, status=status,
                duration_ms=round((time.time() - start) * 1000, 2))

    def log_message(self, *args):  # silence default access log
        pass


if __name__ == "__main__":
    log(level="info", msg="starting", port=PORT, version=VERSION)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
