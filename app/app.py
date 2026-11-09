"""Orders API: the monitored workload.

Endpoints
  GET  /              200 JSON hello
  GET  /health        200 while healthy (ALB health check)
  GET  /fail          500 on purpose (used to trigger alerts)
  POST /orders        202, stores the order as "queued" and enqueues it
                      body (optional JSON): {"item": "pizza", "poison": true}
                      "poison": true makes the worker fail, to exercise retries and the DLQ
  GET  /orders/<id>   order status from DynamoDB (queued -> completed)

Logs are single-line JSON so Datadog/CloudWatch can parse them.
"""
import json
import os
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import boto3

PORT = int(os.environ.get("PORT", "8080"))
ENV = os.environ.get("APP_ENV", "local")
VERSION = os.environ.get("APP_VERSION", "dev")
QUEUE_URL = os.environ.get("QUEUE_URL")
TABLE_NAME = os.environ.get("TABLE_NAME")

sqs = boto3.client("sqs") if QUEUE_URL else None
table = boto3.resource("dynamodb").Table(TABLE_NAME) if TABLE_NAME else None


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

    def _done(self, start, status, **extra):
        if self.path != "/health":  # keep health-check noise out of logs
            log(level="error" if status >= 500 else "info",
                method=self.command, path=self.path, status=status,
                duration_ms=round((time.time() - start) * 1000, 2), **extra)

    def do_GET(self):
        start = time.time()
        if self.path == "/health":
            status, body = 200, {"status": "ok"}
        elif self.path == "/fail":
            status, body = 500, {"status": "error", "reason": "simulated failure"}
        elif self.path.startswith("/orders/"):
            status, body = self._get_order(self.path.rsplit("/", 1)[1])
        else:
            status, body = 200, {"service": "noc-dev", "version": VERSION}
        self._send(status, body)
        self._done(start, status)

    def do_POST(self):
        start = time.time()
        if self.path != "/orders":
            status, body = 404, {"status": "not found"}
        else:
            status, body = self._create_order()
        self._send(status, body)
        self._done(start, status)

    def _create_order(self):
        if not (sqs and table):
            return 503, {"status": "error", "reason": "queue or table not configured"}
        try:
            length = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            return 400, {"status": "error", "reason": "invalid JSON"}
        order_id = str(uuid.uuid4())
        try:
            table.put_item(Item={
                "order_id": order_id,
                "status": "queued",
                "item": str(data.get("item", "unknown")),
                "created_at": int(time.time()),
            })
            sqs.send_message(
                QueueUrl=QUEUE_URL,
                MessageBody=json.dumps({
                    "order_id": order_id,
                    "item": data.get("item", "unknown"),
                    "poison": bool(data.get("poison", False)),
                }),
            )
        except Exception as exc:  # surfaces as a 500 so alerts can see it
            log(level="error", msg="create order failed", error=str(exc))
            return 500, {"status": "error", "reason": "could not create order"}
        return 202, {"order_id": order_id, "status": "queued"}

    def _get_order(self, order_id):
        if not table:
            return 503, {"status": "error", "reason": "table not configured"}
        try:
            item = table.get_item(Key={"order_id": order_id}).get("Item")
        except Exception as exc:
            log(level="error", msg="get order failed", error=str(exc))
            return 500, {"status": "error", "reason": "could not read order"}
        if not item:
            return 404, {"status": "not found"}
        return 200, {k: (int(v) if hasattr(v, "as_tuple") else v) for k, v in item.items()}

    def log_message(self, *args):  # silence default access log
        pass


if __name__ == "__main__":
    log(level="info", msg="starting", port=PORT, version=VERSION)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
