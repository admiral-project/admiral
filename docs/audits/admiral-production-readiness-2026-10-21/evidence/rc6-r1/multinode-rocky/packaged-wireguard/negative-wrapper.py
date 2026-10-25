import json, os, subprocess, sys
credentials = json.load(open("/var/tmp/rc6r1-upload-restore-customer.json", encoding="utf-8"))
env = os.environ.copy()
env.update({
    "HARBOR_TEST_BASE_URL": "https://portal.rc6.test",
    "HARBOR_TEST_HOST_HEADER": "portal.rc6.test",
    "HARBOR_TEST_CA_CERT": "/etc/admiral/tls/ca.pem",
    "HARBOR_TEST_PORTAL_ORIGIN": "https://10.99.0.3:5001",
    "HARBOR_TEST_APP_SLUG": "e2e-upload-restore",
    "HARBOR_TEST_CUSTOMER_EMAIL": credentials["email"],
    "HARBOR_TEST_CUSTOMER_PASSWORD": credentials["password"],
})
result = subprocess.run([
    "python3", "/tmp/issue-182-portal-restore.py", "negative",
    "--instance", "inst_24654c580b2a348c",
    "--slug", "e2e-upload-restore",
    "--backup-id", "upbk_65ee28b65a18",
    "--origin", sys.argv[1],
], env=env, text=True, capture_output=True, check=False)
sys.stdout.write(result.stdout)
sys.stderr.write(result.stderr)
raise SystemExit(result.returncode)
