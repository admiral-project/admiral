#!/usr/bin/env python3
"""Run the customer-facing Harbor portions of issue #182 on a Portal guest.

The generated customer password is kept in a mode-0600 file on the disposable
guest. It is never printed or passed on a command line.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
FLOW = HERE / "independent-portal-customer-flow.py"
RESTORE = HERE / "issue-182-portal-restore.py"
CREDENTIALS = Path("/var/tmp/rc6-r4-issue182-customer.json")
ENV_FILE = Path("/etc/admiral/harbor.env")
BASE_URL = "https://10.99.0.3:5001"
HOST_HEADER = "portal.rc6.test"
CA_CERT = "/etc/admiral/tls/ca.pem"
PORTAL_ORIGIN = "https://10.99.0.3:5001"
APP_SLUG = "e2e-portal-free"


def read_env(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key.strip()] = value.strip().strip("\"'")
    return result


def load_identity() -> dict[str, str]:
    if CREDENTIALS.exists():
        return json.loads(CREDENTIALS.read_text(encoding="utf-8"))
    suffix = secrets.token_hex(6)
    return {
        "email": f"rc6-r4-182-{int(time.time())}-{suffix}@example.test",
        "password": secrets.token_urlsafe(32),
    }


def save_identity(identity: dict[str, str], instance_id: str = "") -> None:
    data = {**identity, "instance_id": instance_id}
    fd = os.open(CREDENTIALS, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as output:
        json.dump(data, output)
        output.write("\n")
    os.chmod(CREDENTIALS, 0o600)


def child_env(identity: dict[str, str]) -> dict[str, str]:
    values = read_env(ENV_FILE)
    required = ("HARBOR_BOOTSTRAP_ADMIN_USER", "HARBOR_BOOTSTRAP_ADMIN_PASSWORD")
    if any(not values.get(key) for key in required):
        raise RuntimeError("Harbor bootstrap admin credentials are unavailable")
    env = os.environ.copy()
    env.update(
        {
            "HARBOR_TEST_BASE_URL": BASE_URL,
            "HARBOR_TEST_HOST_HEADER": HOST_HEADER,
            "HARBOR_TEST_CA_CERT": CA_CERT,
            "HARBOR_TEST_PORTAL_ORIGIN": PORTAL_ORIGIN,
            "HARBOR_TEST_ADMIN_USER": values[required[0]],
            "HARBOR_TEST_ADMIN_PASSWORD": values[required[1]],
            "HARBOR_TEST_CUSTOMER_EMAIL": identity["email"],
            "HARBOR_TEST_CUSTOMER_PASSWORD": identity["password"],
            "HARBOR_TEST_APP_SLUG": APP_SLUG,
            "HARBOR_TEST_APP_DISPLAY_NAME": "E2E Portal Free",
            "HARBOR_TEST_TIER_NAME": "free",
        }
    )
    return env


def run(args: list[str], env: dict[str, str]) -> str:
    result = subprocess.run(args, env=env, text=True, capture_output=True, check=False)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if result.returncode:
        raise RuntimeError(f"customer workflow exited {result.returncode}")
    return result.stdout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("provision-backup", "request-backup", "upload-restore", "restore-existing", "negative", "pause", "resume"))
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--sha256", default="")
    parser.add_argument("--backup-id", default="")
    parser.add_argument("--origin", default="")
    args = parser.parse_args()

    identity = load_identity()
    env = child_env(identity)

    if args.action == "provision-backup":
        flow = run([sys.executable, str(FLOW)], env)
        match = re.search(r"independent_portal_free_deploy=PASS instance_id=(inst_[A-Za-z0-9]+)", flow)
        if not match:
            raise RuntimeError("independent Portal customer flow did not report an instance ID")
        instance_id = match.group(1)
        save_identity(identity, instance_id)
        print(f"customer_instance_id={instance_id}")
        run([sys.executable, str(RESTORE), "request-backup", "--instance", instance_id], env)
    elif args.action == "request-backup":
        if not identity.get("instance_id"):
            raise RuntimeError("customer identity file has no instance ID")
        run([sys.executable, str(RESTORE), "request-backup", "--instance", identity["instance_id"]], env)
    elif args.action == "upload-restore":
        if not identity.get("instance_id") or not args.artifact or not args.sha256:
            parser.error("upload-restore requires an existing customer and --artifact/--sha256")
        actual = hashlib.sha256(args.artifact.read_bytes()).hexdigest()
        if actual != args.sha256:
            raise RuntimeError("backup artifact SHA-256 does not match the supplied digest")
        run(
            [sys.executable, str(RESTORE), "set-origin", "--instance", identity["instance_id"],
             "--origin", PORTAL_ORIGIN],
            env,
        )
        run(
            [sys.executable, str(RESTORE), "upload-pause-restore", "--instance",
             identity["instance_id"], "--slug", APP_SLUG, "--artifact", str(args.artifact),
             "--sha256", args.sha256],
            env,
        )
    elif args.action == "restore-existing":
        if not identity.get("instance_id") or not args.backup_id:
            parser.error("restore-existing requires an existing customer and --backup-id")
        run(
            [sys.executable, str(RESTORE), "set-origin", "--instance", identity["instance_id"],
             "--origin", PORTAL_ORIGIN],
            env,
        )
        run(
            [sys.executable, str(RESTORE), "restore-existing", "--instance", identity["instance_id"],
             "--slug", APP_SLUG, "--backup-id", args.backup_id],
            env,
        )
    elif args.action == "negative":
        if not identity.get("instance_id") or not args.backup_id or not args.origin:
            parser.error("negative requires an existing customer, --backup-id, and --origin")
        run(
            [sys.executable, str(RESTORE), "negative", "--instance", identity["instance_id"],
             "--slug", APP_SLUG, "--backup-id", args.backup_id, "--origin", args.origin],
            env,
        )
    elif args.action == "pause":
        if not identity.get("instance_id"):
            raise RuntimeError("customer identity file has no instance ID")
        run([sys.executable, str(RESTORE), "pause", "--instance", identity["instance_id"]], env)
    else:
        if not identity.get("instance_id"):
            raise RuntimeError("customer identity file has no instance ID")
        run([sys.executable, str(RESTORE), "resume", "--instance", identity["instance_id"]], env)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, KeyError, json.JSONDecodeError) as error:
        print(f"issue_182_harbor_e2e=FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
