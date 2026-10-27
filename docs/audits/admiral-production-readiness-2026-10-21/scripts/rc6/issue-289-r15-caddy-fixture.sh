#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo 'run this fixture as root on the disposable Admin guest' >&2; exit 2; }

candidate='5:0.0.1rc6-15.el10.noarch'
run_dir=/var/tmp/rc6-e5-r15-caddy-fixture
cert_dir=/etc/caddy/rc6-e5-r15-validation
dropin=/etc/systemd/system/admirald.service.d/90-rc6-e5-r15-validation.conf
ca_anchor=/etc/pki/ca-trust/source/anchors/rc6-e5-r15-validation-ca.pem

restore_after_failure() {
    local status=$?
    trap - ERR
    if [[ $status -ne 0 && -d $run_dir ]]; then
        rm -f -- "$dropin"
        systemctl daemon-reload || true
        # Caddy keeps its last accepted Admin API config in memory. Reset that
        # state before removing the temporary certificate it references.
        systemctl restart caddy || true
        systemctl restart admirald || true
        for unit in caddy admirald; do
            for _ in {1..30}; do
                [[ $(systemctl show -p ActiveState --value "$unit") == active && \
                   $(systemctl show -p SubState --value "$unit") == running ]] && break
                sleep 1
            done
        done
        if [[ -s $run_dir/original-acl.txt ]]; then
            setfacl -P --restore="$run_dir/original-acl.txt" || true
        fi
        rm -f -- "$ca_anchor"
        update-ca-trust extract || true
        rm -rf -- "$cert_dir" "$run_dir"
    fi
    exit "$status"
}
trap restore_after_failure ERR

actual=$(rpm -q --qf '%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}' admiral-common)
[[ $actual == "$candidate" ]] || { echo "unexpected admiral-common candidate: $actual" >&2; exit 1; }
[[ -r /etc/admiral/tls/ca.pem && -r /etc/admiral/tls/ca-key.pem ]]
[[ ! -e $run_dir && ! -e $cert_dir && ! -e $dropin && ! -e $ca_anchor ]]

install -d -o root -g root -m 0700 "$run_dir"
getfacl -p /etc/admiral /etc/admiral/tls /etc/admiral/tls/ca.pem >"$run_dir/original-acl.txt"
chmod 0600 "$run_dir/original-acl.txt"

install -d -o root -g caddy -m 0750 "$cert_dir"
openssl req -new -newkey rsa:2048 -sha256 -nodes \
    -keyout "$run_dir/privkey.pem" -out "$run_dir/leaf.csr" \
    -subj '/CN=portal.rc6.test' \
    -addext 'subjectAltName=DNS:portal.rc6.test,DNS:apps.rc6.test,DNS:probe.apps.rc6.test,DNS:*.apps.rc6.test,DNS:flagship.rc6.test,DNS:cockpit.rc6.test' \
    >/dev/null 2>&1
cat >"$run_dir/leaf.ext" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:portal.rc6.test,DNS:apps.rc6.test,DNS:probe.apps.rc6.test,DNS:*.apps.rc6.test,DNS:flagship.rc6.test,DNS:cockpit.rc6.test
EOF
openssl x509 -req -in "$run_dir/leaf.csr" \
    -CA /etc/admiral/tls/ca.pem -CAkey /etc/admiral/tls/ca-key.pem \
    -set_serial 5150015 -days 2 -sha256 -extfile "$run_dir/leaf.ext" \
    -out "$run_dir/leaf.pem" >/dev/null 2>&1
cat "$run_dir/leaf.pem" /etc/admiral/tls/ca.pem >"$cert_dir/fullchain.pem"
install -o root -g caddy -m 0640 "$run_dir/privkey.pem" "$cert_dir/privkey.pem"
chown root:caddy "$cert_dir/fullchain.pem"
chmod 0644 "$cert_dir/fullchain.pem"
runuser -u caddy -- test -r "$cert_dir/fullchain.pem"
runuser -u caddy -- test -r "$cert_dir/privkey.pem"

setfacl -m u:caddy:--x /etc/admiral /etc/admiral/tls
setfacl -m u:caddy:r-- /etc/admiral/tls/ca.pem
install -o root -g root -m 0644 /etc/admiral/tls/ca.pem "$ca_anchor"
restorecon -F "$ca_anchor"
update-ca-trust extract

install -d -o root -g root -m 0755 "$(dirname "$dropin")"
cat >"$dropin" <<EOF
[Service]
Environment="ADMIRAL_NETWORKING_BASE_DOMAIN=rc6.test"
Environment="ADMIRAL_NETWORKING_PORTAL_HOSTNAME=portal.rc6.test"
Environment="ADMIRAL_NETWORKING_PORTAL_TARGET=https://10.99.0.2:5001"
Environment="ADMIRAL_NETWORKING_APPS_DOMAIN=apps.rc6.test"
Environment="ADMIRAL_NETWORKING_APPS_REDIRECT_TO=portal.rc6.test"
Environment="ADMIRAL_NETWORKING_TLS_CERT_FILE=$cert_dir/fullchain.pem"
Environment="ADMIRAL_NETWORKING_TLS_KEY_FILE=$cert_dir/privkey.pem"
Environment="ADMIRAL_TLS_CA_FILE=/etc/admiral/tls/ca.pem"
EOF
chmod 0644 "$dropin"
systemctl daemon-reload
systemctl restart admirald
route_ready=0
for _ in {1..30}; do
    if [[ $(systemctl show -p ActiveState --value admirald) == active && \
          $(systemctl show -p SubState --value admirald) == running && \
          $(systemctl show -p ActiveState --value caddy) == active && \
          $(systemctl show -p SubState --value caddy) == running ]] && \
       curl --fail --silent --max-time 3 http://127.0.0.1:2019/config/ |
       python3 -c 'import json,sys; d=json.load(sys.stdin); text=json.dumps(d); assert "portal.rc6.test" in text; assert "/etc/caddy/rc6-e5-r15-validation/fullchain.pem" in text' >/dev/null 2>&1; then
        route_ready=1
        break
    fi
    sleep 1
done
[[ $route_ready -eq 1 ]]
[[ $(systemctl show -p ActiveState --value admirald) == active ]]
[[ $(systemctl show -p SubState --value caddy) == running ]]

openssl verify -CAfile /etc/admiral/tls/ca.pem -purpose sslserver \
    -verify_hostname portal.rc6.test "$cert_dir/fullchain.pem"
openssl verify -CAfile /etc/admiral/tls/ca.pem -purpose sslserver \
    -verify_hostname probe.apps.rc6.test "$cert_dir/fullchain.pem"

result=$(curl --silent --show-error --max-time 10 \
    --cacert /etc/admiral/tls/ca.pem \
    --resolve portal.rc6.test:443:127.0.0.1 \
    -o "$run_dir/portal-register-response" \
    -w '%{http_code} %{ssl_verify_result}' \
    https://portal.rc6.test/auth/register)
[[ $result == '200 0' ]]
[[ -s $run_dir/portal-register-response ]]

printf 'candidate_admiral_common=%s\n' "$actual"
printf 'portal_upstream=https://10.99.0.2:5001\n'
printf 'portal_route_local_strict_tls=%s\n' "$result"
printf 'portal_certificate_sha256=%s\n' "$(openssl x509 -in "$cert_dir/fullchain.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
printf 'caddy_fixture=ACTIVE\n'
