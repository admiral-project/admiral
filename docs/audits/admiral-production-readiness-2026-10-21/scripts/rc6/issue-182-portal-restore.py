#!/usr/bin/env python3
"""Drive issue #182 upload/restore checks through the independent Harbor UI."""

from __future__ import annotations

import argparse
import hashlib
import html
import importlib.util
import os
from pathlib import Path
import re
import ssl
import subprocess
import sys
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request


_helper_path = Path(__file__).with_name("independent-portal-customer-flow.py")
_spec = importlib.util.spec_from_file_location("rc6_portal_helpers", _helper_path)
if _spec is None or _spec.loader is None:
    raise RuntimeError("could not load the independent portal HTTP helpers")
_helpers = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_helpers)
Portal = _helpers.Portal
csrf_for = _helpers.csrf_for
portal_origin = os.environ.get("HARBOR_TEST_PORTAL_ORIGIN", "https://10.99.0.3:5001")


def portal() -> Portal:
    base = os.environ["HARBOR_TEST_BASE_URL"]
    if urlparse(base).scheme != "https":
        raise RuntimeError("portal origin must use HTTPS")
    return Portal(base, os.environ["HARBOR_TEST_HOST_HEADER"])


def login(client: Portal) -> None:
    email = os.environ["HARBOR_TEST_CUSTOMER_EMAIL"]
    password = os.environ["HARBOR_TEST_CUSTOMER_PASSWORD"]
    status, _, body = client.request("/auth/login")
    if status != 200:
        raise RuntimeError(f"login page returned HTTP {status}")
    status, final, _ = client.request(
        "/auth/login",
        method="POST",
        csrf=csrf_for(body),
        data={"email": email, "password": password},
    )
    if status != 200 or urlparse(final).path != "/client/":
        raise RuntimeError("customer login failed")


def instance_page(client: Portal, instance_id: str) -> tuple[str, str]:
    path = f"/client/instances/{instance_id}"
    status, _, body = client.request(path)
    if status != 200:
        raise RuntimeError(f"customer instance page returned HTTP {status}")
    return path, body


def post_form(client: Portal, path: str, body: str, data: dict[str, str]) -> str:
    status, final, result = client.request(
        path,
        method="POST",
        csrf=csrf_for(body),
        data={**data, "csrf_token": csrf_for(body)},
    )
    if status != 200:
        raise RuntimeError(f"POST {path} returned HTTP {status}")
    expected_path = path
    for suffix in ("/actions", "/restore"):
        if expected_path.endswith(suffix):
            expected_path = expected_path[: -len(suffix)]
    if urlparse(final).path != expected_path:
        raise RuntimeError(f"POST {path} redirected to an unexpected page")
    return result


def request_backup(client: Portal, instance_id: str) -> None:
    path, body = instance_page(client, instance_id)
    result = post_form(
        client,
        f"{path}/actions",
        body,
        {"action": "backup", "service": "db"},
    )
    match = re.search(r"(?:operation\s+|Operation ID:\s*)(op_[A-Za-z0-9]+)", result, re.IGNORECASE)
    if match is None:
        raise RuntimeError("customer backup action did not return an operation ID")
    print(f"customer_backup_operation={match.group(1)}")


def resume(client: Portal, instance_id: str) -> None:
    path, body = instance_page(client, instance_id)
    result = post_form(client, f"{path}/actions", body, {"action": "resume"})
    match = re.search(r"operation\s+(op_[A-Za-z0-9]+)", result, re.IGNORECASE)
    if match is None:
        raise RuntimeError("customer resume action did not return an operation ID")
    print(f"customer_resume_operation={match.group(1)}")


def upload(client: Portal, instance_id: str, artifact: Path, expected_sha: str) -> str:
    data = artifact.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    if sha != expected_sha:
        raise RuntimeError("local backup artifact SHA-256 differs from the Admiral backup record")
    _, page = instance_page(client, instance_id)
    csrf = csrf_for(page)
    boundary = "----admiral-rc6-issue182-boundary"
    body = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="csrf_token"\r\n\r\n'
        f"{csrf}\r\n"
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="backup_file"; filename="admiral-backup.tar.gz"\r\n'
        "Content-Type: application/gzip\r\n\r\n"
    ).encode() + data + f"\r\n--{boundary}--\r\n".encode()
    url = client.base_url + f"/client/instances/{instance_id}/backups/upload"
    req = Request(
        url,
        data=body,
        headers={
            "Host": client.host,
            "Accept": "text/html",
            "X-CSRF-Token": csrf,
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
        method="POST",
    )
    try:
        with client.opener.open(req, timeout=60) as response:
            status, final, page = response.status, response.geturl(), response.read().decode("utf-8", "replace")
    except HTTPError as error:
        status, final, page = error.code, error.geturl(), error.read().decode("utf-8", "replace")
    if status != 200 or urlparse(final).path != f"/client/instances/{instance_id}":
        raise RuntimeError(f"backup upload returned HTTP {status} or unexpected redirect")
    if "Backup uploaded and ready for restore" not in page:
        raise RuntimeError("Harbor did not confirm the backup upload")
    ids = set(re.findall(r"/client/uploaded-backups/(upbk_[A-Za-z0-9]+)/download", page))
    if len(ids) != 1:
        raise RuntimeError(f"expected one uploaded-backup ID on the owner page, found {len(ids)}")
    backup_id = ids.pop()
    download_url = client.base_url + f"/client/uploaded-backups/{backup_id}/download"
    with client.opener.open(Request(download_url, headers={"Host": client.host}), timeout=60) as response:
        downloaded = response.read()
    downloaded_sha = hashlib.sha256(downloaded).hexdigest()
    if len(downloaded) != len(data) or downloaded_sha != expected_sha:
        raise RuntimeError("owner download did not match the uploaded source size and SHA-256")
    print(f"uploaded_backup_id={backup_id}")
    print(f"owner_download_bytes={len(downloaded)} sha256={downloaded_sha}")
    return backup_id


def pause(client: Portal, instance_id: str) -> None:
    path, body = instance_page(client, instance_id)
    post_form(client, f"{path}/actions", body, {"action": "pause"})
    for attempt in range(60):
        _, body = instance_page(client, instance_id)
        visible = re.sub(r"<[^>]+>", " ", body)
        visible = re.sub(r"\s+", " ", visible)
        if re.search(r"Operational\s+Paused(?:\s|$)", visible, re.IGNORECASE):
            print(f"customer_pause=confirmed polls={attempt + 1}")
            return
        import time

        time.sleep(2)
    raise RuntimeError("instance did not become paused within 120 seconds")


def request_restore(client: Portal, instance_id: str, slug: str, backup_id: str) -> str:
    path, body = instance_page(client, instance_id)
    result = post_form(
        client,
        f"{path}/restore",
        body,
        {
            "source_kind": "uploaded",
            "source_backup_id": backup_id,
            "service_name": "db",
            "confirm_text": slug,
        },
    )
    match = re.search(r"Restore queued with operation\s+(op_[A-Za-z0-9]+)", result, re.IGNORECASE)
    if match is None:
        excerpt = re.sub(r"<[^>]+>", " ", result)
        excerpt = html.unescape(re.sub(r"\s+", " ", excerpt)).strip()
        excerpt = re.sub(r"(https?://[^?\s]+)\?[^\s]+", r"\1?<redacted>", excerpt)
        raise RuntimeError(
            "uploaded restore was not queued; response did not contain a restore operation; "
            f"response={excerpt[:1200]}"
        )
    print(f"uploaded_restore_operation={match.group(1)}")
    return match.group(1)


def negative_restore(client: Portal, instance_id: str, slug: str, backup_id: str, origin: str) -> None:
    if origin not in {"https://10.99.0.2:5001", "https://169.254.169.254:5001"}:
        raise RuntimeError("negative test origin is not on the fixed untrusted-origin allowlist")
    set_origin(origin)
    try:
        path, body = instance_page(client, instance_id)
        result = post_form(
            client,
            f"{path}/restore",
            body,
            {
                "source_kind": "uploaded",
                "source_backup_id": backup_id,
                "service_name": "db",
                "confirm_text": slug,
            },
        )
        text = re.sub(r"<[^>]+>", " ", result)
        if "Restore request failed" not in text or "Restore queued with operation" in text:
            raise RuntimeError(f"untrusted origin was not rejected by Admirald: {origin}; response excerpt={text[:1800]!r}")
        error = re.search(r"Restore request failed:\s*(.{1,240}?)(?:\s{2,}|$)", text)
        detail = re.sub(r"\s+", " ", error.group(1)).strip() if error else "Admirald rejected the restore request"
        print(f"untrusted_restore_origin_rejected={origin} error={detail}")
    finally:
        set_origin(portal_origin)


def set_origin(origin: str) -> None:
    if origin not in {
        portal_origin,
        "https://10.99.0.3:5001",
        "https://10.99.0.100:5001",
        "https://10.99.0.2:5001",
        "https://169.254.169.254:5001",
    }:
        raise RuntimeError("portal origin is not on the fixed validation allowlist")
    completed = subprocess.run(
        [
            "sudo", "-u", "postgres", "psql", "-X", "-q", "-v", "ON_ERROR_STOP=1",
            "-d", "admiral_harbor", "-c",
            "INSERT INTO harbor_meta(key,value,updated_at) "
            f"VALUES ('harbor_external_url','{origin}',now()) "
            "ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_at=now()",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError("could not restore the valid Harbor origin")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("request-backup", "upload-pause-restore", "restore-existing", "pause", "resume", "negative", "set-origin"))
    parser.add_argument("--instance", required=True)
    parser.add_argument("--slug", default=os.environ.get("HARBOR_TEST_APP_SLUG", "e2e-upload-restore"))
    parser.add_argument("--backup-id", default="")
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--sha256", default="")
    parser.add_argument("--origin", default="")
    args = parser.parse_args()
    client = portal()
    login(client)
    if args.action == "request-backup":
        request_backup(client, args.instance)
    elif args.action == "upload-pause-restore":
        if not args.artifact or not args.sha256:
            parser.error("upload-pause-restore requires --artifact and --sha256")
        backup_id = upload(client, args.instance, args.artifact, args.sha256)
        pause(client, args.instance)
        request_restore(client, args.instance, args.slug, backup_id)
    elif args.action == "restore-existing":
        if not args.backup_id:
            parser.error("restore-existing requires --backup-id")
        request_restore(client, args.instance, args.slug, args.backup_id)
    elif args.action == "pause":
        pause(client, args.instance)
    elif args.action == "resume":
        resume(client, args.instance)
    elif args.action == "negative":
        if not args.backup_id or not args.origin:
            parser.error("negative requires --backup-id and --origin")
        negative_restore(client, args.instance, args.slug, args.backup_id, args.origin)
    else:
        if not args.origin:
            parser.error("set-origin requires --origin")
        set_origin(args.origin)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, RuntimeError) as error:
        print(f"issue_182_portal_restore=FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
