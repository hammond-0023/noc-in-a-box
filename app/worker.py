"""Order worker: long-polls SQS, "processes" each order, marks it completed.

Failure handling (the NOC-relevant part):
  - On error the message is NOT deleted. SQS makes it visible again after the
    visibility timeout; after 3 failed receives it moves to the dead-letter queue.
  - Messages with "poison": true always fail, so you can trigger this on demand.
"""
import json
import os
import sys
import time

import boto3

ENV = os.environ.get("APP_ENV", "local")
QUEUE_URL = os.environ["QUEUE_URL"]
TABLE_NAME = os.environ["TABLE_NAME"]
PROCESS_SECONDS = float(os.environ.get("PROCESS_SECONDS", "2"))

sqs = boto3.client("sqs")
table = boto3.resource("dynamodb").Table(TABLE_NAME)


def log(**fields):
    fields["ts"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    fields["env"] = ENV
    fields["service"] = "worker"
    sys.stdout.write(json.dumps(fields) + "\n")
    sys.stdout.flush()


def process(message):
    body = json.loads(message["Body"])
    order_id = body["order_id"]
    attempt = int(message["Attributes"].get("ApproximateReceiveCount", "1"))
    start = time.time()
    try:
        if body.get("poison"):
            raise ValueError("poison message")
        time.sleep(PROCESS_SECONDS)
        table.update_item(
            Key={"order_id": order_id},
            UpdateExpression="SET #s = :s, completed_at = :t",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":s": "completed", ":t": int(time.time())},
        )
        sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=message["ReceiptHandle"])
        log(level="info", msg="order completed", order_id=order_id, attempt=attempt,
            duration_ms=round((time.time() - start) * 1000, 2))
    except Exception as exc:
        log(level="error", msg="order failed", order_id=order_id, attempt=attempt,
            error=str(exc))


def main():
    log(level="info", msg="worker starting", queue=QUEUE_URL)
    while True:
        resp = sqs.receive_message(
            QueueUrl=QUEUE_URL,
            MaxNumberOfMessages=5,
            WaitTimeSeconds=10,
            AttributeNames=["ApproximateReceiveCount"],
        )
        for message in resp.get("Messages", []):
            process(message)


if __name__ == "__main__":
    main()
