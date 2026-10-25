#!/usr/bin/env python3
"""Verify complete Harbor admin mutation redirects over the Portal WireGuard origin.

Run as root on the dedicated Portal guest. Admin bootstrap credentials are read
from /etc/admiral/harbor.env and are never printed or placed in argv.
"""

from __future__ import annotations

from html.parser import HTMLParser
import http.cookiejar
import os
import re
import secrets
import ssl
import sys
import time
from urllib.error import HTTPError
from urllib.parse import urlencode, urljoin, urlparse
from urllib.request import HTTPCookieProcessor, HTTPSHandler, Request, build_opener, HTTPRedirectHandler


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.csrf = ""
        self.forms: list[dict[str, str]] = []
        self.form: dict[str, str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key: value or "" for key, value in attrs}
        if tag == "meta" and values.get("name") == "csrf-token":
            self.csrf = values.get("content", "")
        elif tag == "form":
            self.form = {"__action__": values.get("action", "")}
        elif tag == "input" and self.form is not None:
            name = values.get("name", "")
            if name:
                self.form[name] = values.get("value", "")

    def handle_endtag(self, tag: str) -> None:
        if tag == "form" and self.form is not None:
            self.forms.append(self.form)
            self.form = None


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        return None


def csrf(body: str) -> str:
    page = Page()
    page.feed(body)
    if page.csrf:
        return page.csrf
    for form in page.forms:
        if form.get("csrf_token"):
            return form["csrf_token"]
    raise RuntimeError("page has no CSRF token")


class Session:
    def __init__(self, base_url: str, ca_file: str) -> None:
        self.base_url = base_url.rstrip("/")
        context = ssl.create_default_context(cafile=ca_file)
        self.opener = build_opener(
            HTTPCookieProcessor(http.cookiejar.CookieJar()),
            HTTPSHandler(context=context),
            NoRedirect(),
        )

    def request(self, path: str, method: str = "GET", fields: dict[str, str] | None = None):
        url = urljoin(self.base_url + "/", path.lstrip("/"))
        data = urlencode(fields).encode() if fields is not None else None
        headers = {"Accept": "text/html,application/json;q=0.9,*/*;q=0.8"}
        if data is not None:
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        request = Request(url, data=data, headers=headers, method=method)
        try:
            with self.opener.open(request, timeout=20) as response:
                return response.status, response.headers, response.read().decode("utf-8", "replace")
        except HTTPError as response:
            return response.code, response.headers, response.read().decode("utf-8", "replace")


def read_bootstrap_credentials(path: str) -> tuple[str, str]:
    values: dict[str, str] = {}
    with open(path, encoding="utf-8") as source:
        for line in source:
            if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
                continue
            key, value = line.rstrip("\r\n").split("=", 1)
            values[key] = value.strip().strip("\"'")
    user = values.get("HARBOR_BOOTSTRAP_ADMIN_USER", "")
    password = values.get("HARBOR_BOOTSTRAP_ADMIN_PASSWORD", "")
    if not user or not password:
        raise RuntimeError("Harbor admin bootstrap credentials are missing")
    return user, password


def require(ok: bool, message: str) -> None:
    if not ok:
        raise RuntimeError(message)


def assert_empty_redirect(label: str, result, expected_prefix: str) -> str:
    status, headers, body = result
    location = headers.get("Location", "")
    length = headers.get("Content-Length", "")
    print(f"{label}_status={status}")
    print(f"{label}_location={location}")
    print(f"{label}_content_length={length or '(absent)'}")
    print(f"{label}_body_bytes={len(body.encode())}")
    require(status == 303, f"{label} returned HTTP {status}, expected 303")
    require(len(body.encode()) == 0, f"{label} returned a non-empty body")
    require(length in ("", "0"), f"{label} declared an unexpected body length {length}")
    require(bool(location) and urlparse(urljoin("https://portal/", location)).path.startswith(expected_prefix),
            f"{label} redirect target was unexpected: {location!r}")
    return location


def main() -> int:
    base_url = os.environ.get("HARBOR_TEST_BASE_URL", "https://10.99.0.3:5001")
    ca_file = os.environ.get("HARBOR_TEST_CA_CERT", "/etc/admiral/tls/ca.pem")
    require(urlparse(base_url).scheme == "https", "Portal origin must use HTTPS")
    admin_user, admin_password = read_bootstrap_credentials("/etc/admiral/harbor.env")
    admin = Session(base_url, ca_file)

    status, _, login_page = admin.request("/admin/login")
    require(status == 200, f"admin login page returned HTTP {status}")
    status, headers, _ = admin.request("/admin/login", "POST", {
        "username": admin_user,
        "password": admin_password,
        "csrf_token": csrf(login_page),
    })
    login_location = headers.get("Location", "")
    require(status in (302, 303) and urlparse(urljoin(base_url, login_location)).path != "/admin/login",
            "admin login did not establish a session")
    print("admin_login=PASS")

    customer = Session(base_url, ca_file)
    status, _, register_page = customer.request("/auth/register")
    require(status == 200, f"registration page returned HTTP {status}")
    timestamp = time.strftime("%Y%m%d%H%M%S", time.gmtime())
    email = f"rc6-issue289-{timestamp}-{secrets.token_hex(3)}@example.test"
    customer_password = secrets.token_urlsafe(24)
    status, headers, _ = customer.request("/auth/register", "POST", {
        "display_name": "RC6 Harbor redirect regression",
        "email": email,
        "password": customer_password,
        "country": "US",
        "accept_terms": "1",
        "csrf_token": csrf(register_page),
    })
    require(status in (302, 303) and urlparse(urljoin(base_url, headers.get("Location", ""))).path == "/auth/login",
            "synthetic signup did not remain pending")
    print(f"synthetic_pending_signup={email}")

    status, _, pending_page = admin.request("/admin/review_user")
    require(status == 200 and email in pending_page, "synthetic pending customer is absent from the review queue")
    match = re.search(
        r"<tr\b[^>]*>(?:(?!</tr>).)*?<code>\s*" + re.escape(email)
        + r"\s*</code>(?:(?!</tr>).)*?<form[^>]+action=\"([^\"]*/review[-_]user/(\d+)/approve)",
        pending_page,
        re.IGNORECASE | re.DOTALL,
    )
    require(match is not None, "could not find the synthetic customer's approval form")
    approval_path = urlparse(match.group(1)).path
    expected_review_path = re.sub(r"/\d+/approve$", "", approval_path)
    approval = admin.request(approval_path, "POST", {"csrf_token": csrf(pending_page)})
    location = assert_empty_redirect("approval", approval, expected_review_path)
    follow_status, _, _ = admin.request(urlparse(urljoin(base_url, location)).path)
    require(follow_status == 200, f"approval redirect follow-up returned HTTP {follow_status}")
    print("approval_redirect_followup=HTTP 200")

    status, _, login_page = customer.request("/auth/login")
    require(status == 200, f"customer login page returned HTTP {status}")
    status, headers, _ = customer.request("/auth/login", "POST", {
        "email": email,
        "password": customer_password,
        "csrf_token": csrf(login_page),
    })
    customer_location = headers.get("Location", "")
    require(status in (302, 303) and urlparse(urljoin(base_url, customer_location)).path.startswith("/client"),
            "approved synthetic customer could not log in")
    print("approved_customer_login=PASS")

    status, _, dashboard = admin.request("/admin/")
    require(status == 200, f"admin dashboard returned HTTP {status}")
    sync = admin.request("/admin/catalog/sync", "POST", {"csrf_token": csrf(dashboard)})
    location = assert_empty_redirect("catalog_sync", sync, "/admin")
    follow_status, _, _ = admin.request(urlparse(urljoin(base_url, location)).path)
    require(follow_status == 200, f"catalog redirect follow-up returned HTTP {follow_status}")
    print("catalog_redirect_followup=HTTP 200")
    print("issue_289_direct_portal=PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(f"issue_289_direct_portal=FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
