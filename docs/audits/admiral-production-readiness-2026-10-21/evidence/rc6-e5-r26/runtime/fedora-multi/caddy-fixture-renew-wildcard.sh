#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo 'run this fixture as root on Admin' >&2; exit 2; }

domain='portal.r26.test'
run_dir=/var/tmp/rc6-e5-r26-caddy-fixture
cert_dir=/etc/caddy/rc6-e5-r26-validation
dropin=/etc/systemd/system/admirald.service.d/90-rc6-e5-r26-validation.conf
fullchain="$cert_dir/fullchain.pem"
privkey="$cert_dir/privkey.pem"
upstream='https://10.99.0.3:5001'

[[ -s $run_dir/privkey.pem && -s /etc/admiral/tls/ca.pem && -s /etc/admiral/tls/ca-key.pem ]]
[[ -s $fullchain && -s $privkey && -f $dropin ]]
grep -Fq "ADMIRAL_NETWORKING_PORTAL_HOSTNAME=$domain" "$dropin"

openssl req -new -key "$run_dir/privkey.pem" -sha256 \
    -out "$run_dir/leaf-wildcard.csr" -subj "/CN=$domain" \
    -addext 'subjectAltName=DNS:portal.r26.test,DNS:apps.r26.test,DNS:probe.apps.r26.test,DNS:*.apps.r26.test,DNS:flagship.r26.test,DNS:cockpit.r26.test' \
    >/dev/null 2>&1
cat >"$run_dir/leaf-wildcard.ext" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:portal.r26.test,DNS:apps.r26.test,DNS:probe.apps.r26.test,DNS:*.apps.r26.test,DNS:flagship.r26.test,DNS:cockpit.r26.test
EOF
openssl x509 -req -in "$run_dir/leaf-wildcard.csr" \
    -CA /etc/admiral/tls/ca.pem -CAkey /etc/admiral/tls/ca-key.pem \
    -set_serial 26102802 -days 2 -sha256 -extfile "$run_dir/leaf-wildcard.ext" \
    -out "$run_dir/leaf-wildcard.pem" >/dev/null 2>&1
cat "$run_dir/leaf-wildcard.pem" /etc/admiral/tls/ca.pem >"$fullchain.new"
chown root:caddy "$fullchain.new"
chmod 0644 "$fullchain.new"
mv -f -- "$fullchain.new" "$fullchain"
restorecon -F "$fullchain"
runuser -u caddy -- test -r "$fullchain"
runuser -u caddy -- test -r "$privkey"

openssl verify -CAfile /etc/admiral/tls/ca.pem -purpose sslserver \
    -verify_hostname portal.r26.test "$fullchain"
openssl verify -CAfile /etc/admiral/tls/ca.pem -purpose sslserver \
    -verify_hostname ${APP_HOST:-e2e-portal-free247575.apps.r26.test} "$fullchain"

systemctl restart admirald
for _ in {1..30}; do
    [[ $(systemctl show -p ActiveState --value admirald) == active && \
       $(systemctl show -p SubState --value admirald) == running && \
       $(systemctl show -p ActiveState --value caddy) == active && \
       $(systemctl show -p SubState --value caddy) == running ]] && break
    sleep 1
done
systemctl is-active --quiet admirald
systemctl is-active --quiet caddy

portal_result=$(curl --silent --show-error --fail --max-time 10 \
    --cacert /etc/admiral/tls/ca.pem --resolve portal.r26.test:443:127.0.0.1 \
    --output /dev/null --write-out '%{http_code} %{ssl_verify_result}' \
    https://portal.r26.test/auth/register)
[[ $portal_result == '200 0' ]]
printf 'caddy_certificate_sans=portal.r26.test,*.apps.r26.test,flagship.r26.test,cockpit.r26.test\n'
printf 'caddy_certificate_sha256=%s\n' "$(openssl x509 -in "$fullchain" -noout -fingerprint -sha256 | cut -d= -f2)"
printf 'portal_route_local_strict_tls=%s\n' "$portal_result"
printf 'caddy_upstream=%s\n' "$upstream"
printf 'caddy_fixture=ACTIVE\n'
