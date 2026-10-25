#!/usr/bin/env python3
"""Probe Harbor UI, forged customer actions, and ownership for issue #181."""

from __future__ import annotations

import os
import json
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import re
import ssl
import sys
import time
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

flow_spec = spec_from_file_location(
    "independent_portal_customer_flow",
    Path(__file__).with_name("independent-portal-customer-flow.py"),
)
if flow_spec is None or flow_spec.loader is None:
    raise RuntimeError("could not load the independent Portal flow helpers")
flow_module = module_from_spec(flow_spec)
flow_spec.loader.exec_module(flow_module)
Portal = flow_module.Portal
csrf_for = flow_module.csrf_for


def login(portal: Portal, email: str, password: str) -> None:
    status, _, body = portal.request("/auth/login")
    if status != 200:
        raise RuntimeError(f"login page returned HTTP {status}")
    csrf = csrf_for(body)
    status, final_url, body = portal.request(
        "/auth/login", method="POST", csrf=csrf,
        data={"email": email, "password": password},
    )
    if status != 200 or urlparse(final_url).path != "/client/":
        raise RuntimeError("customer login failed or account is not approved")


def customer_api(method: str, path: str, payload: dict[str, object]) -> tuple[int, str]:
    base = os.environ["HARBOR_TEST_ADMIRAL_API_URL"].rstrip("/")
    token = os.environ["HARBOR_TEST_ADMIRAL_API_TOKEN"]
    customer_id = os.environ["HARBOR_TEST_CUSTOMER_ID"]
    ca_file = os.environ["HARBOR_TEST_ADMIRAL_CA_CERT"]
    request = Request(
        base + path,
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "X-Admiral-Customer-ID": customer_id,
            "X-Admiral-Operator": "admiral-harbor",
            "Content-Type": "application/json",
        },
        method=method,
    )
    context = ssl.create_default_context(cafile=ca_file or None)
    try:
        with urlopen(request, context=context, timeout=30) as response:
            return response.status, response.read().decode("utf-8", "replace")
    except HTTPError as error:
        return error.code, error.read().decode("utf-8", "replace")


def main() -> int:
    base_url = os.environ["HARBOR_TEST_BASE_URL"]
    host = os.environ["HARBOR_TEST_HOST_HEADER"]
    instance_id = os.environ["HARBOR_TEST_INSTANCE_ID"]
    slug = os.environ["HARBOR_TEST_APP_SLUG"]
    owner_email = os.environ["HARBOR_TEST_CUSTOMER_EMAIL"]
    owner_password = os.environ["HARBOR_TEST_CUSTOMER_PASSWORD"]
    other_email = os.environ["HARBOR_TEST_OTHER_EMAIL"]
    other_password = os.environ["HARBOR_TEST_OTHER_PASSWORD"]
    admin_user = os.environ["HARBOR_TEST_ADMIN_USER"]
    admin_password = os.environ["HARBOR_TEST_ADMIN_PASSWORD"]

    owner = Portal(base_url, host)
    login(owner, owner_email, owner_password)
    path = f"/client/instances/{instance_id}"
    status, _, detail = owner.request(path)
    if status != 200:
        raise RuntimeError(f"owner instance page returned HTTP {status}")
    if "Request backup" in detail or 'name="source_kind"' in detail:
        raise RuntimeError("disallowed backup or restore control is visible")
    print("issue_181_disallowed_controls=hidden")

    csrf = csrf_for(detail)
    status, final_url, detail = owner.request(
        f"/client/instances/{instance_id}/actions", method="POST", csrf=csrf,
        data={"action": "backup", "service": "db", "csrf_token": csrf},
    )
    if status != 200 or urlparse(final_url).path != path:
        raise RuntimeError(f"forged backup action returned HTTP {status}")
    if "Action failed" not in detail or "disabled for this tier" not in detail:
        raise RuntimeError("forged database backup was not rejected by the tier policy")
    print("issue_181_forged_database_backup=denied")
    status, body = customer_api(
        "POST", "/api/v1/customer-apps/action",
        {"instance_id": instance_id, "action": "backup", "service": "db"},
    )
    if status != 403 or "Manual database backups are disabled for this tier" not in body:
        raise RuntimeError(f"customer backup API returned HTTP {status}: {body}")
    print(f"issue_181_api_backup_http={status} body={body.strip()}")

    status, _, detail = owner.request(path)
    csrf = csrf_for(detail)
    status, final_url, detail = owner.request(
        f"/client/instances/{instance_id}/actions", method="POST", csrf=csrf,
        data={"action": "pause", "csrf_token": csrf},
    )
    if status != 200 or urlparse(final_url).path != path:
        raise RuntimeError(f"pause action returned HTTP {status}")
    for _ in range(60):
        status, _, detail = owner.request(path)
        if status == 200 and "Paused" in detail:
            break
        time.sleep(2)
    else:
        raise RuntimeError("instance did not reach the paused state within 120 seconds")
    csrf = csrf_for(detail)
    status, final_url, detail = owner.request(
        f"/client/instances/{instance_id}/restore", method="POST", csrf=csrf,
        data={
            "source_kind": "remote", "source_backup_id": "", "service_name": "db",
            "confirm_text": slug, "csrf_token": csrf,
        },
    )
    if status != 200 or urlparse(final_url).path != path:
        raise RuntimeError(f"forged restore action returned HTTP {status}")
    if "Restore request failed" not in detail or "disabled for this tier" not in detail:
        raise RuntimeError("forged restore request was not rejected by the tier policy")
    print("issue_181_forged_restore=denied")
    status, body = customer_api(
        "POST", f"/api/v1/customer-apps/{instance_id}/backups/restore",
        {
            "backup_id": "", "target_app_id": instance_id, "service": "db",
            "source": {}, "verify_checksum": True, "restore_mode": "replace",
        },
    )
    if status != 403 or "Restore is disabled for this tier" not in body:
        raise RuntimeError(f"customer restore API returned HTTP {status}: {body}")
    print(f"issue_181_api_restore_http={status} body={body.strip()}")

    # Register and approve a second disposable customer to exercise the
    # ownership boundary with a distinct authenticated principal.
    other = Portal(base_url, host)
    status, _, page = other.request("/auth/register")
    if status != 200:
        raise RuntimeError(f"second registration page returned HTTP {status}")
    csrf = csrf_for(page)
    status, final_url, _ = other.request(
        "/auth/register", method="POST", csrf=csrf,
        data={
            "display_name": "RC6 Issue 181 Other Customer", "email": other_email,
            "password": other_password, "country": "US", "accept_terms": "1",
        },
    )
    if status != 200 or urlparse(final_url).path != "/auth/login":
        raise RuntimeError("second customer registration did not enter pending state")

    admin = Portal(base_url, host)
    status, _, page = admin.request("/admin/login")
    if status != 200:
        raise RuntimeError(f"admin login page returned HTTP {status}")
    csrf = csrf_for(page)
    status, final_url, _ = admin.request(
        "/admin/login", method="POST", csrf=csrf,
        data={"username": admin_user, "password": admin_password, "csrf_token": csrf},
    )
    if status != 200 or urlparse(final_url).path == "/admin/login":
        raise RuntimeError("Harbor admin login failed")
    status, _, pending = admin.request("/admin/review_user")
    if status != 200 or other_email not in pending:
        raise RuntimeError("second customer missing from pending review queue")
    match = re.search(
        r"<tr\b[^>]*>(?:(?!</tr>).)*?<code>\s*" + re.escape(other_email)
        + r"\s*</code>(?:(?!</tr>).)*?<form[^>]+action=\"([^\"]*/review[-_]user/(\d+)/approve)\"",
        pending, re.IGNORECASE | re.DOTALL,
    )
    if match is None:
        raise RuntimeError("could not find second customer's approval control")
    csrf = csrf_for(pending)
    status, _, _ = admin.request(
        urlparse(match.group(1)).path, method="POST", csrf=csrf,
        data={"csrf_token": csrf},
    )
    if status != 200:
        raise RuntimeError("could not approve second disposable customer")
    login(other, other_email, other_password)
    status, _, _ = other.request(path)
    if status != 404:
        raise RuntimeError(f"another customer got HTTP {status} for the owner's instance")
    print("issue_181_cross_customer_instance_access=404")
    print("issue_181_customer_policy_probe=PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, RuntimeError) as error:
        print(f"issue_181_customer_policy_probe=FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
