#!/usr/bin/env python3
# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

"""
admiral_https_setup - Post-install HTTPS for Admiral.

Obtains a Let's Encrypt wildcard certificate via DNS-01 ACME challenge
for *.apps.<DOMAIN>, then configures admirald to use it.
The DNS TXT step is interactive and is intentionally not handled by Ansible.

Admirald manages Caddy routes dynamically via its Admin API.
This script only provisions the certificate and sets the env vars.

Usage:
    sudo admiral_https_setup
    sudo admiral_https_setup --domain cloud.example.com
    sudo admiral_https_setup --domain testcloud.example.com
"""

import argparse
import grp
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def fail(msg):
    print(f"[FATAL] {msg}", file=sys.stderr)
    sys.exit(1)


def info(msg):
    print(f"[INFO] {msg}")


def ok(msg):
    print(f"[ OK ] {msg}")


def warn(msg):
    print(f"[WARN] {msg}")


def check_root():
    if os.geteuid() != 0:
        fail("Root privileges required. Run with sudo.")


def check_requirements():
    missing = []
    for cmd in ("certbot", "openssl"):
        if not _which(cmd):
            missing.append(cmd)
    if missing:
        fail(
            f"Missing: {', '.join(missing)}. Install them:\n"
            f"  dnf install -y {' '.join(missing)}"
        )


def _which(cmd):
    return shutil.which(cmd)


def detect_public_ip():
    import json
    import urllib.request

    for url in (
        "https://api.ipify.org?format=json",
        "https://checkip.amazonaws.com",
    ):
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": "admiral-https-setup/0.1",
            })
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = resp.read().decode().strip()
                if url.endswith("json"):
                    return json.loads(data).get("ip")
                return data
        except Exception:
            continue
    return None


def get_local_ips():
    import fcntl
    import struct

    ips = set()
    for iface in os.listdir("/sys/class/net/"):
        if iface == "lo":
            continue
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            ifr = struct.pack("256s", iface[:15].encode())
            raw = fcntl.ioctl(sock, 0x8915, ifr)
            ips.add(socket.inet_ntoa(raw[20:24]))
        except Exception:
            continue
    return ips


def normalize_domain_input(value):
    if not value:
        fail("Base domain cannot be empty.")

    raw_value = value.strip()
    if not raw_value:
        fail("Base domain cannot be empty.")

    candidate = raw_value
    if "://" in candidate:
        parsed = urllib.parse.urlparse(candidate)
        if not parsed.hostname:
            fail(f"Could not extract a hostname from '{raw_value}'.")
        if parsed.path not in ("", "/") or parsed.params or parsed.query or parsed.fragment:
            fail(
                "Pass only the base URL or hostname. Paths, query strings, and fragments are not allowed."
            )
        candidate = parsed.hostname

    candidate = candidate.strip().rstrip(".").lower()

    if candidate.startswith("*."):
        fail(
            f"'{raw_value}' looks like a wildcard record. Pass the base domain instead, "
            "for example 'testcloud.example.com'."
        )

    for prefix in ("admin.", "portal.", "flagship.", "cockpit."):
        if candidate.startswith(prefix):
            fail(
                f"'{raw_value}' points to a specific service host. Pass the shared base domain instead, "
                "for example 'testcloud.example.com'."
            )

    if candidate.startswith("apps."):
        fail(
            f"'{raw_value}' points to the apps wildcard domain. Pass the parent base domain instead, "
            "for example 'testcloud.example.com'."
        )

    if "." not in candidate:
        fail(
            f"'{raw_value}' is not a full public domain name. If your DNS provider shows relative record names "
            "such as '*.apps.testcloud' and '*.testcloud', pass the full base domain for that zone, "
            "for example 'testcloud.example.com'."
        )

    if not re.match(r"^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$", candidate):
        fail(f"'{raw_value}' is not a valid public domain name.")

    return candidate


def validate_domain(domain):
    domain = normalize_domain_input(domain)

    apps_domain = f"apps.{domain}"

    public_ip = detect_public_ip()
    local_ips = get_local_ips()

    info(f"Base domain:    {domain}")
    info(f"Apps domain:    {apps_domain}")
    info(f"Wildcard cert:  *.{apps_domain}")
    info(f"Public IP:      {public_ip or 'unable to detect'}")
    info("")

    # Resolve key hostnames
    for name, host in [("domain", domain), ("apps", apps_domain)]:
        try:
            resolved = socket.getaddrinfo(host, 80)
            ips = set(r[4][0] for r in resolved)
            info(f"  {name} -> {ips}")
            if public_ip and public_ip not in ips:
                warn(f"DNS for {host} does not point to this server's IP ({public_ip})")
        except socket.gaierror:
            warn(f"  {host} does not resolve in public DNS")

    return domain, apps_domain


def run_certbot_wildcard(domain, apps_domain):
    info("=" * 60)
    info("WILDCARD CERTIFICATE VIA DNS-01 CHALLENGE")
    info("=" * 60)
    info("")
    info(f"Admiral needs a wildcard certificate for *.{apps_domain}")
    info("to avoid Let's Encrypt rate limit (50 certs/domain/week).")
    info("")
    info("This flow is manual.")
    info("certbot will pause and ask you to publish one or more DNS TXT records.")
    info("Each time certbot prints a TXT challenge:")
    info("  1. Create the TXT record in your DNS provider.")
    info("  2. Wait for public DNS propagation.")
    info("  3. Return here and continue.")
    info("")
    info("Important:")
    info(f"  - TXT record name: _acme-challenge.{apps_domain}")
    info("  - certbot may request more than one TXT value with the same name")
    info("  - if that happens, keep the previous TXT values and add the new one too")
    info("  - do not replace or delete earlier TXT values during the same certbot run")
    info("  - failed validation does not permanently block the domain, but repeated failures")
    info("    can trigger temporary Let's Encrypt rate limits")
    info("  - do not retry until the required TXT records are publicly visible")
    info("")
    info("Before starting, make sure these public records already exist:")
    info(f"  - {domain} -> A -> this server public IP")
    info(f"  - *.{domain} -> A -> this server public IP")
    info(f"  - *.{apps_domain} -> A -> this server public IP")
    info("")
    input("Press Enter to begin the certbot challenge...")

    # Prompt for email
    email = input(
        "Email for Let's Encrypt (leave blank for no notifications): "
    ).strip()

    cmd = [
        "certbot", "certonly", "--manual",
        "--preferred-challenges", "dns",
        "-d", f"*.{apps_domain}",
        "-d", apps_domain,
        "--agree-tos",
    ]
    if email:
        cmd.extend(["--email", email])
    else:
        cmd.append("--register-unsafely-without-email")

    info("")
    info("certbot will show you the TXT record to add.")
    info("Add it to your DNS, wait for propagation, then confirm.")
    info("If certbot asks for a second TXT with the same name, add it without removing the first one.")
    info("")

    result = subprocess.run(cmd)
    if result.returncode != 0:
        fail(
            "certbot failed. Before retrying, verify that:\n"
            f"  - {domain} resolves publicly to this VPS\n"
            f"  - _acme-challenge.{apps_domain} publishes every TXT value requested in the same run\n"
            "  - your DNS provider is not replacing the previous TXT when adding a new one\n"
            "After that, re-run:\n"
            "  sudo admiral_https_setup"
        )

    cert_dir = f"/etc/letsencrypt/live/{apps_domain}"
    if not os.path.isdir(cert_dir):
        fail(f"Certificate directory not found: {cert_dir}")

    ok(f"Certificate obtained: *.{apps_domain}")
    return cert_dir


def _read_ini(key):
    ini_path = "/etc/admirald.ini"
    if not os.path.isfile(ini_path):
        return None
    with open(ini_path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            if k.strip() == key:
                return v.strip()
    return None


def _validate_certificate_pair(cert_file, key_file):
    cert_pub = subprocess.check_output(
        ["openssl", "x509", "-in", cert_file, "-pubkey", "-noout"], text=True
    )
    key_pub = subprocess.check_output(
        ["openssl", "pkey", "-in", key_file, "-pubout"], text=True
    )
    if cert_pub != key_pub:
        fail("Certificate and private key do not contain the same public key.")


def _dns_name_matches(pattern, hostname):
    pattern = pattern.lower()
    hostname = hostname.lower()
    if pattern == hostname:
        return True
    if not pattern.startswith("*."):
        return False

    suffix = pattern[1:]
    # Wildcards only match exactly one left-most DNS label.
    return hostname.endswith(suffix) and hostname.count(".") == suffix.count(".")

def _certificate_dns_names(cert_file):
    try:
        output = subprocess.check_output(
            ["openssl", "x509", "-in", cert_file, "-noout", "-ext", "subjectAltName"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, OSError) as exc:
        fail(f"Unable to read subjectAltName from {cert_file}: {exc}")

    return [match.lower() for match in re.findall(r"DNS:([^,\s]+)", output)]


def _validate_certificate_usage(cert_file):
    try:
        usage_output = subprocess.check_output(
            [
                "openssl",
                "x509",
                "-in",
                cert_file,
                "-noout",
                "-ext",
                "extendedKeyUsage",
                "-ext",
                "keyUsage",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, OSError) as exc:
        fail(f"Unable to read certificate usage extensions from {cert_file}: {exc}")

    if not re.search(r"(TLS\s+Web\s+Server\s+Authentication|Server\s+Authentication)", usage_output, re.IGNORECASE):
        fail("Certificate is not valid for TLS server authentication (missing serverAuth EKU).")
    if not re.search(r"Digital\s+Signature", usage_output, re.IGNORECASE):
        fail("Certificate keyUsage must allow digitalSignature for TLS server authentication.")


def _validate_certificate_names(cert_file, apps_domain):
    cert_names = _certificate_dns_names(cert_file)
    if not cert_names:
        fail("Certificate is missing subjectAltName DNS entries.")

    for hostname in (apps_domain, f"probe.{apps_domain}"):
        if not any(_dns_name_matches(pattern, hostname) for pattern in cert_names):
            fail(f"Certificate does not cover required hostname {hostname}.")


def _deploy_readonly_certificate(cert_file, key_file, deploy_dir="/etc/admiral/tls/letsencrypt"):
    caddy_group = grp.getgrnam("caddy")
    os.makedirs(deploy_dir, mode=0o750, exist_ok=True)
    os.chown(deploy_dir, 0, caddy_group.gr_gid)
    os.chmod(deploy_dir, 0o750)
    for source, name, mode in ((cert_file, "fullchain.pem", 0o644), (key_file, "privkey.pem", 0o640)):
        destination = os.path.join(deploy_dir, name)
        temporary = f"{destination}.tmp"
        shutil.copyfile(source, temporary)
        os.chown(temporary, 0, caddy_group.gr_gid)
        os.chmod(temporary, mode)
        os.replace(temporary, destination)
    return (
        os.path.join(deploy_dir, "fullchain.pem"),
        os.path.join(deploy_dir, "privkey.pem"),
    )


def _validate_target(name, value):
    if not value or any(char in value for char in "\r\n"):
        fail(f"{name} must be a non-empty URL without newlines")
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        fail(f"{name} must be an http(s) URL with a hostname")
    try:
        parsed.port
    except ValueError:
        fail(f"{name} contains an invalid port")


def _verify_public_https(domain):
    failures = []
    for service, path in (("portal", "/health"), ("flagship", "/health"), ("cockpit", "/")):
        url = f"https://{service}.{domain}{path}"
        last_error = "unknown error"
        for _ in range(6):
            try:
                with urllib.request.urlopen(url, timeout=10) as response:
                    if response.status < 500:
                        last_error = ""
                        break
                    last_error = f"HTTP {response.status}"
            except urllib.error.HTTPError as exc:
                if exc.code < 500:
                    last_error = ""
                    break
                last_error = f"HTTP {exc.code}"
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                last_error = str(exc)
            time.sleep(5)
        if last_error:
            failures.append(f"{url}: {last_error}")
    if failures:
        raise RuntimeError("public HTTPS health checks failed: " + "; ".join(failures))


def configure_admirald(domain, apps_domain, cert_dir):
    cert_file = f"{cert_dir}/fullchain.pem"
    key_file = f"{cert_dir}/privkey.pem"

    for f in (cert_file, key_file):
        if not os.path.isfile(f):
            fail(f"Missing: {f}")

    _validate_certificate_pair(cert_file, key_file)
    _validate_certificate_usage(cert_file)
    _validate_certificate_names(cert_file, apps_domain)
    override_dir = "/etc/systemd/system/admirald.service.d"
    os.makedirs(override_dir, exist_ok=True)

    # Preserve existing targets from env or INI, fall back to single-node TLS
    # upstream defaults. Fixed public hosts use Caddy-managed ACME certificates;
    # only apps.<domain> uses the manually provisioned wildcard certificate.
    portal_target = os.environ.get(
        "ADMIRAL_NETWORKING_PORTAL_TARGET",
        _read_ini("networking_portal_target") or "https://127.0.0.1:5001",
    )
    flagship_target = os.environ.get(
        "ADMIRAL_NETWORKING_FLAGSHIP_TARGET",
        _read_ini("networking_flagship_target") or "https://127.0.0.1:5000",
    )
    cockpit_target = os.environ.get(
        "ADMIRAL_NETWORKING_COCKPIT_TARGET",
        _read_ini("networking_cockpit_target") or "http://127.0.0.1:9090",
    )
    for target_name, target in (("portal target", portal_target), ("Flagship target", flagship_target), ("Cockpit target", cockpit_target)):
        _validate_target(target_name, target)

    deploy_dir = "/etc/admiral/tls/letsencrypt"
    deployed_paths = (os.path.join(deploy_dir, "fullchain.pem"), os.path.join(deploy_dir, "privkey.pem"))
    previous_certificates = {
        path: Path(path).read_bytes() if os.path.exists(path) else None
        for path in deployed_paths
    }
    deployed_cert_file, deployed_key_file = _deploy_readonly_certificate(cert_file, key_file, deploy_dir)

    override_content = f"""[Service]
Environment=ADMIRAL_NETWORKING_BASE_DOMAIN={domain}
Environment=ADMIRAL_NETWORKING_APPS_DOMAIN={apps_domain}
Environment=ADMIRAL_NETWORKING_PORTAL_TARGET={portal_target}
Environment=ADMIRAL_NETWORKING_FLAGSHIP_TARGET={flagship_target}
Environment=ADMIRAL_NETWORKING_COCKPIT_TARGET={cockpit_target}
Environment=ADMIRAL_NETWORKING_TLS_CERT_FILE={deployed_cert_file}
Environment=ADMIRAL_NETWORKING_TLS_KEY_FILE={deployed_key_file}
"""
    override_path = os.path.join(override_dir, "10-https.conf")
    previous = None
    if os.path.exists(override_path):
        with open(override_path, "rb") as f:
            previous = f.read()
    temporary_override = f"{override_path}.tmp"
    with open(temporary_override, "w") as f:
        f.write(override_content)
    os.chmod(temporary_override, 0o644)
    os.replace(temporary_override, override_path)
    ok(f"Wrote {override_path}")

    try:
        subprocess.run(["systemctl", "daemon-reload"], capture_output=True, check=True)
        subprocess.run(["systemd-analyze", "verify", "admirald.service"], check=True, capture_output=True, text=True)
        for service in ("caddy", "admirald"):
            subprocess.run(["systemctl", "restart", service], capture_output=True, check=True)
            subprocess.run(["systemctl", "is-active", "--quiet", service], check=True)
        _verify_public_https(domain)
    except (subprocess.CalledProcessError, OSError, RuntimeError) as exc:
        if previous is None:
            os.unlink(override_path)
        else:
            with open(override_path, "wb") as f:
                f.write(previous)
        subprocess.run(["systemctl", "daemon-reload"], capture_output=True)
        for path, content in previous_certificates.items():
            if content is None:
                if os.path.exists(path):
                    os.unlink(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
                os.chmod(path, 0o640 if path.endswith("privkey.pem") else 0o644)
        for service in ("caddy", "admirald"):
            subprocess.run(["systemctl", "restart", service], capture_output=True)
        fail(f"HTTPS activation failed and previous configuration was restored: {exc}")

    # admirald will push the full config including TLS cert to Caddy Admin API
    ok("caddy and admirald restarted — routes and TLS will resync automatically")


def print_summary(domain, apps_domain):
    print()
    print("=" * 60)
    print("HTTPS configuration complete.")
    print("=" * 60)
    print()
    print(f"  Wildcard certificate:  *.{apps_domain}")
    print(f"  Portal:                https://portal.{domain}")
    print(f"  Flagship:              https://flagship.{domain}")
    print(f"  Cockpit:               https://cockpit.{domain}")
    print(f"  App instances:         https://<app><6digits>.{apps_domain}")
    print()
    print("Public TLS model:")
    print(f"  - Caddy manages ACME for portal.{domain}, flagship.{domain}, cockpit.{domain}")
    print(f"  - Wildcard certificate *.{apps_domain} is reserved for app instances")
    print()
    print("Renewal:")
    print("  certbot renew --deploy-hook /usr/libexec/admiral-letsencrypt-deploy-hook")
    print()
    print("For automated renewal, install a certbot DNS plugin or use")
    print("a systemd timer calling certbot renew.")
    print()
    listener = _read_ini("listen_address") or "unknown"
    info(f"Effective Admirald listen address from /etc/admirald.ini: {listener}:8080")
    print("=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description="Configure HTTPS for Admiral via Let's Encrypt wildcard.",
    )
    parser.add_argument(
        "--domain", "-d",
        dest="base_domain",
        help=(
            "Base domain or base URL. Pass the public base domain, for example "
            "'testcloud.example.com' or 'https://testcloud.example.com'."
        ),
    )
    parser.add_argument(
        "--base-url",
        dest="base_domain",
        help="Alias for --domain. Accepts a base URL or hostname.",
    )
    args = parser.parse_args()

    check_root()
    check_requirements()

    domain = args.base_domain or input(
        "Base domain or base URL "
        "(e.g. testcloud.example.com or https://testcloud.example.com): "
    ).strip()
    domain, apps_domain = validate_domain(domain)

    cert_dir = run_certbot_wildcard(domain, apps_domain)
    configure_admirald(domain, apps_domain, cert_dir)
    print_summary(domain, apps_domain)


if __name__ == "__main__":
    main()
