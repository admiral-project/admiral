#!/usr/bin/env python3
"""Launch the independent Harbor customer flow through Admin Caddy."""

from __future__ import annotations

from datetime import UTC, datetime
import os
from pathlib import Path
import secrets
import sys


HERE = Path(__file__).resolve().parent
DRIVER = HERE / "independent-portal-customer-flow.py"


def main() -> None:
    admin_user = os.environ.get("HARBOR_BOOTSTRAP_ADMIN_USER", "")
    admin_password = os.environ.get("HARBOR_BOOTSTRAP_ADMIN_PASSWORD", "")
    if not admin_user or not admin_password:
        raise SystemExit("Harbor bootstrap admin credentials are unavailable")

    suffix = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ").lower() + "-" + secrets.token_hex(3)
    email = f"rc6-e5-caddy-{suffix}@example.test"
    env = os.environ.copy()
    env.update(
        {
            "HARBOR_TEST_BASE_URL": os.environ.get("HARBOR_TEST_BASE_URL", "https://portal.rc6.test"),
            "HARBOR_TEST_HOST_HEADER": os.environ.get("HARBOR_TEST_HOST_HEADER", "portal.rc6.test"),
            "HARBOR_TEST_CA_CERT": os.environ.get("HARBOR_TEST_CA_CERT", "/etc/admiral/tls/ca.pem"),
            "HARBOR_TEST_ADMIN_USER": admin_user,
            "HARBOR_TEST_ADMIN_PASSWORD": admin_password,
            "HARBOR_TEST_CUSTOMER_EMAIL": email,
            "HARBOR_TEST_CUSTOMER_PASSWORD": secrets.token_urlsafe(32),
            "HARBOR_TEST_APP_SLUG": "e2e-portal-free",
            "HARBOR_TEST_APP_DISPLAY_NAME": "E2E Portal Free",
            "HARBOR_TEST_TIER_NAME": "free",
        }
    )
    print(f"routed_portal_test_email={email}", flush=True)
    os.execve(sys.executable, [sys.executable, str(DRIVER)], env)


if __name__ == "__main__":
    main()
