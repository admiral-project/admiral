#!/usr/bin/env python3
"""Poll one customer-scoped operation through Harbor's installed API client."""

import json
import sys
import time

from app import create_app
from app.admiral_client import get_operation


def main() -> int:
    if len(sys.argv) not in {4, 5}:
        raise SystemExit("usage: issue-295-poll-operation.py OPERATION_ID INSTANCE_ID CUSTOMER_ID [TIMEOUT_SECONDS]")
    operation_id, instance_id, customer_id = sys.argv[1:4]
    timeout = int(sys.argv[4]) if len(sys.argv) == 5 else 180
    deadline = time.monotonic() + timeout
    app = create_app()
    with app.app_context():
        while True:
            operation = get_operation(operation_id, instance_id=instance_id, customer_id=customer_id)
            observed = {
                key: operation.get(key)
                for key in ("id", "action", "status", "instance_id", "node_id", "error_message")
            }
            print(json.dumps(observed, sort_keys=True), flush=True)
            status = operation.get("status")
            if status in {"succeeded", "failed", "cancelled"}:
                if status != "succeeded":
                    raise SystemExit(f"operation ended in {status!r}")
                print("deprovision_operation=succeeded PASS", flush=True)
                return 0
            if time.monotonic() >= deadline:
                raise SystemExit(f"operation did not complete within {timeout} seconds")
            time.sleep(2)


if __name__ == "__main__":
    raise SystemExit(main())
