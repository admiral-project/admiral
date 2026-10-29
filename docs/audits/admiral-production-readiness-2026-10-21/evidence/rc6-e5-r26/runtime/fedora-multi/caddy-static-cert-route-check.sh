#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo 'run as root on Admin' >&2; exit 2; }

run_dir=$(mktemp -d /run/rc6-e5-r26-caddy-static-cert.XXXXXX)
admin_api=http://127.0.0.1:2019
certificate=/etc/caddy/rc6-e5-r26-validation/fullchain.pem
private_key=/etc/caddy/rc6-e5-r26-validation/privkey.pem
ca=/etc/admiral/tls/ca.pem
portal_host=portal.r26.test
app_host=${APP_HOST:-e2e-portal-free582790.apps.r26.test}

cleanup() {
    if [[ -s $run_dir/baseline.json ]]; then
        curl --silent --show-error --fail --max-time 5 \
            --request POST --header 'Content-Type: application/json' \
            --data-binary "@$run_dir/baseline.json" "$admin_api/load" >/dev/null || true
    fi
    rm -rf -- "$run_dir"
}
trap cleanup EXIT

[[ -s $certificate && -s $private_key && -s $ca ]]
curl --silent --show-error --fail --max-time 5 "$admin_api/config/" >"$run_dir/baseline.json"
jq --arg certificate "$certificate" --arg private_key "$private_key" \
    '.apps.tls.certificates.load_files = ((.apps.tls.certificates.load_files // []) + [{certificate: $certificate, key: $private_key}])' \
    "$run_dir/baseline.json" >"$run_dir/with-static-certificate.json"
curl --silent --show-error --fail --max-time 5 \
    --request POST --header 'Content-Type: application/json' \
    --data-binary "@$run_dir/with-static-certificate.json" "$admin_api/load" >/dev/null

portal_result=$(curl --silent --show-error --fail --max-time 10 \
    --cacert "$ca" --resolve "$portal_host:443:127.0.0.1" \
    --output /dev/null --write-out '%{http_code} %{ssl_verify_result}' \
    "https://$portal_host/auth/register")
app_result=$(curl --silent --show-error --fail --max-time 10 \
    --cacert "$ca" --resolve "$app_host:443:127.0.0.1" \
    --output /dev/null --write-out '%{http_code} %{ssl_verify_result}' \
    "https://$app_host/")
[[ $portal_result == '200 0' ]]
[[ $app_result == '200 0' ]]
printf 'portal_route_strict_tls_http=%s\n' "$portal_result"
printf 'worker_workload_host=%s\n' "$app_host"
printf 'worker_workload_route_strict_tls_http=%s\n' "$app_result"
printf 'fixture_static_certificate_sha256=%s\n' "$(openssl x509 -in "$certificate" -noout -fingerprint -sha256 | cut -d= -f2)"
