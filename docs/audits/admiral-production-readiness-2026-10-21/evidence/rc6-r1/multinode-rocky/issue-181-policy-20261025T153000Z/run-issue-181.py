#!/usr/bin/env python3
"""Orchestrate the packaged-candidate Harbor tier-policy E2E without persisting credentials."""
from __future__ import annotations
import os
import re
import secrets
import subprocess
import sys
from datetime import datetime, timezone

flow_script = "/tmp/rc6-independent-portal-customer-flow.py"
probe_script = "/tmp/rc6-backup-policy-customer-probe.py"
env = os.environ.copy()
suffix = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S") + "-" + secrets.token_hex(4)
env.update({
    "HARBOR_TEST_BASE_URL": "https://portal.rc6.test",
    "HARBOR_TEST_HOST_HEADER": "portal.rc6.test",
    "HARBOR_TEST_CA_CERT": "/etc/admiral/tls/ca.pem",
    "HARBOR_TEST_ADMIN_USER": env["HARBOR_BOOTSTRAP_ADMIN_USER"],
    "HARBOR_TEST_ADMIN_PASSWORD": env["HARBOR_BOOTSTRAP_ADMIN_PASSWORD"],
    "HARBOR_TEST_CUSTOMER_EMAIL": f"rc6-r1-issue181-{suffix}@example.test",
    "HARBOR_TEST_CUSTOMER_PASSWORD": secrets.token_hex(24),
    "HARBOR_TEST_OTHER_EMAIL": f"rc6-r1-issue181-other-{suffix}@example.test",
    "HARBOR_TEST_OTHER_PASSWORD": secrets.token_hex(24),
    "HARBOR_TEST_APP_SLUG": "e2e-backup-policy",
    "HARBOR_TEST_APP_DISPLAY_NAME": "E2E Backup Policy",
    "HARBOR_TEST_TIER_NAME": "free",
})

def run(script: str) -> str:
    result = subprocess.run([sys.executable, script], env=env, text=True, capture_output=True)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode:
        raise SystemExit(result.returncode)
    return result.stdout

flow = run(flow_script)
customer = re.search(r"^independent_portal_customer_approved=id:(\d+)$", flow, re.M)
instance = re.search(r"^independent_portal_free_deploy=PASS instance_id=(inst_[A-Za-z0-9]+)$", flow, re.M)
if not customer or not instance:
    raise SystemExit("customer flow omitted approved customer or deployed instance id")
query = (
    "from sqlalchemy import create_engine,text; import os,sys; "
    "e=create_engine(os.environ['HARBOR_DATABASE_URL']); "
    "c=e.connect(); r=c.execute(text('SELECT public_id FROM customer WHERE email=:email'), "
    "{'email':sys.argv[1]}).scalar_one(); print(r); c.close(); e.dispose()"
)
lookup = subprocess.run(
    [sys.executable, "-c", query, env["HARBOR_TEST_CUSTOMER_EMAIL"]],
    env=env, text=True, capture_output=True, check=True,
)
customer_public_id = lookup.stdout.strip()
if not customer_public_id.startswith("hcus_"):
    raise SystemExit("Harbor customer DB did not return a valid public Admiral customer id")
env.update({
    "HARBOR_TEST_ADMIRAL_API_TOKEN": env["ADMIRAL_HARBOR_API_TOKEN"],
    "HARBOR_TEST_ADMIRAL_API_URL": env["ADMIRAL_API_URL"],
    "HARBOR_TEST_ADMIRAL_CA_CERT": env["ADMIRAL_CA_FILE"],
    "HARBOR_TEST_CUSTOMER_ID": customer_public_id,
    "HARBOR_TEST_INSTANCE_ID": instance.group(1),
})
run(probe_script)
print("issue_181_candidate=0.0.1rc6-1-no-explicit-epoch")
print(f"issue_181_harbor_user_id={customer.group(1)}")
print(f"issue_181_admiral_customer_id={customer_public_id}")
print(f"issue_181_instance_id={instance.group(1)}")
print(f"issue_181_generated_accounts={env['HARBOR_TEST_CUSTOMER_EMAIL']},{env['HARBOR_TEST_OTHER_EMAIL']}")
