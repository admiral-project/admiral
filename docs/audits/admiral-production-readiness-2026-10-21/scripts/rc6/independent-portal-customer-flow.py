#!/usr/bin/env python3
"""Exercise the independent Harbor portal through its public Caddy route."""

from __future__ import annotations

from html.parser import HTMLParser
import http.cookiejar
import os
import re
import ssl
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urljoin, urlparse
from urllib.request import HTTPCookieProcessor, HTTPSHandler, Request, build_opener


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.csrf = ""
        self.forms: list[dict[str, str]] = []
        self._form: dict[str, str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key: value or "" for key, value in attrs}
        if tag == "meta" and values.get("name") == "csrf-token":
            self.csrf = values.get("content", "")
        elif tag == "form":
            self._form = {"__action__": values.get("action", "")}
        elif tag == "input" and self._form is not None:
            name = values.get("name", "")
            if name and values.get("type", "text").lower() != "password":
                self._form[name] = values.get("value", "")

    def handle_endtag(self, tag: str) -> None:
        if tag == "form" and self._form is not None:
            self.forms.append(self._form)
            self._form = None


class Portal:
    def __init__(self, base_url: str, host: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.cookies = http.cookiejar.CookieJar()
        # The routed hostname's CA/name are verified by the separate curl gate;
        # urllib connects to the private lab admin address while preserving Host.
        context = ssl._create_unverified_context()
        self.opener = build_opener(HTTPCookieProcessor(self.cookies), HTTPSHandler(context=context))
        self.host = host

    def request(
        self,
        path: str,
        method: str = "GET",
        data: dict[str, str] | None = None,
        csrf: str = "",
    ) -> tuple[int, str, str]:
        url = urljoin(self.base_url + "/", path.lstrip("/"))
        body = urlencode(data).encode() if data is not None else None
        headers = {"Host": self.host, "Accept": "text/html,application/json;q=0.9,*/*;q=0.8"}
        if body is not None:
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        if csrf:
            headers["X-CSRF-Token"] = csrf
        req = Request(url, data=body, headers=headers, method=method)
        try:
            with self.opener.open(req, timeout=30) as response:
                return response.status, response.geturl(), response.read().decode("utf-8", "replace")
        except HTTPError as error:
            return error.code, error.geturl(), error.read().decode("utf-8", "replace")
        except URLError as error:
            raise RuntimeError(f"{method} {path} failed: {error.reason}") from error


def parse(body: str) -> Page:
    page = Page()
    page.feed(body)
    return page


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def csrf_for(body: str) -> str:
    page = parse(body)
    if page.csrf:
        return page.csrf
    for form in page.forms:
        if form.get("csrf_token"):
            return form["csrf_token"]
    raise RuntimeError("page did not expose a CSRF token")


def main() -> int:
    base_url = os.environ["HARBOR_TEST_BASE_URL"]
    host = os.environ["HARBOR_TEST_HOST_HEADER"]
    admin_user = os.environ["HARBOR_TEST_ADMIN_USER"]
    admin_password = os.environ["HARBOR_TEST_ADMIN_PASSWORD"]
    customer_email = os.environ["HARBOR_TEST_CUSTOMER_EMAIL"]
    customer_password = os.environ["HARBOR_TEST_CUSTOMER_PASSWORD"]
    slug = "e2e-portal-free"
    require(urlparse(base_url).scheme == "https", "portal test URL must use HTTPS")

    customer = Portal(base_url, host)
    status, _, page = customer.request("/auth/register")
    require(status == 200, f"registration page returned HTTP {status}")
    csrf = csrf_for(page)
    status, final_url, page = customer.request(
        "/auth/register",
        method="POST",
        csrf=csrf,
        data={
            "display_name": "RC6 Independent Portal Test",
            "email": customer_email,
            "password": customer_password,
            "country": "US",
            "accept_terms": "1",
        },
    )
    require(status == 200 and urlparse(final_url).path == "/auth/login", "signup did not create a pending account")
    print("independent_portal_signup=pending")

    status, _, page = customer.request("/auth/login")
    csrf = csrf_for(page)
    status, final_url, page = customer.request(
        "/auth/login",
        method="POST",
        csrf=csrf,
        data={"email": customer_email, "password": customer_password},
    )
    require(
        status == 200 and urlparse(final_url).path == "/auth/login" and "pending activation" in page.lower(),
        "pending customer login was not rejected",
    )
    print("independent_portal_pending_login=rejected")

    admin = Portal(base_url, host)
    status, _, page = admin.request("/admin/login")
    require(status == 200, f"Harbor admin login page returned HTTP {status}")
    csrf = csrf_for(page)
    status, final_url, page = admin.request(
        "/admin/login",
        method="POST",
        csrf=csrf,
        data={"username": admin_user, "password": admin_password, "csrf_token": csrf},
    )
    require(status == 200 and urlparse(final_url).path != "/admin/login", "Harbor admin login failed")

    status, _, pending = admin.request("/admin/review_user")
    require(status == 200 and customer_email in pending, "pending customer is absent from Harbor review queue")
    match = re.search(
        r"<tr\b[^>]*>(?:(?!</tr>).)*?<code>\s*" + re.escape(customer_email)
        + r"\s*</code>(?:(?!</tr>).)*?<form[^>]+action=\"([^\"]*/review[-_]user/(\d+)/approve)\"",
        pending,
        re.IGNORECASE | re.DOTALL,
    )
    require(match is not None, "could not locate the matching Harbor approval form")
    approve_path = urlparse(match.group(1)).path
    customer_id = match.group(2)
    csrf = csrf_for(pending)
    status, _, _ = admin.request(approve_path, method="POST", csrf=csrf, data={"csrf_token": csrf})
    require(status == 200, "Harbor admin could not approve the pending customer")
    print(f"independent_portal_customer_approved=id:{customer_id}")

    status, _, dashboard = admin.request("/admin/")
    require(status == 200, "Harbor admin dashboard unavailable after approval")
    csrf = csrf_for(dashboard)
    status, _, _ = admin.request("/admin/catalog/sync", method="POST", csrf=csrf, data={"csrf_token": csrf})
    require(status == 200, "Harbor catalog sync failed")
    status, _, app_page = admin.request(f"/admin/apps/{slug}")
    require(status == 200 and slug in app_page, "test app missing from Harbor admin catalog")
    csrf = csrf_for(app_page)
    status, _, _ = admin.request(
        f"/admin/apps/{slug}", method="POST", csrf=csrf, data={"published": "on", "csrf_token": csrf}
    )
    require(status == 200, "publishing the free test app failed")
    print("independent_portal_catalog=published")

    status, _, page = customer.request("/auth/login")
    csrf = csrf_for(page)
    status, final_url, page = customer.request(
        "/auth/login",
        method="POST",
        csrf=csrf,
        data={"email": customer_email, "password": customer_password},
    )
    require(status == 200 and urlparse(final_url).path == "/client/", "approved customer login failed")
    status, _, catalog = customer.request("/catalog")
    require(status == 200 and "E2E Portal Free" in catalog, "published app is not visible in portal catalog")
    status, _, app_page = customer.request(f"/apps/{slug}")
    require(status == 200 and 'name="tier_name" value="free"' in app_page, "free app tier is not deployable")
    csrf = csrf_for(app_page)
    status, final_url, page = customer.request(
        f"/client/apps/{slug}/deploy",
        method="POST",
        csrf=csrf,
        data={"tier_name": "free", "csrf_token": csrf},
    )
    require(status == 200, f"customer free deployment returned HTTP {status}")
    match = re.search(r"/client/instances/(inst_[A-Za-z0-9]+)/welcome", urlparse(final_url).path)
    require(match is not None and match.group(1) in page, "deployment did not reach its instance confirmation page")
    instance_id = match.group(1)
    print(f"independent_portal_free_deploy=PASS instance_id={instance_id}")
    print("independent_portal_customer_flow=PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, RuntimeError) as error:
        print(f"independent_portal_customer_flow=FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
