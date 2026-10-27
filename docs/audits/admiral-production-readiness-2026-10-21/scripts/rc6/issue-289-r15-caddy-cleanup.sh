#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo 'run this cleanup as root on the disposable Admin guest' >&2; exit 2; }
run_dir=/var/tmp/rc6-e5-r15-caddy-fixture
cert_dir=/etc/caddy/rc6-e5-r15-validation
dropin=/etc/systemd/system/admirald.service.d/90-rc6-e5-r15-validation.conf
ca_anchor=/etc/pki/ca-trust/source/anchors/rc6-e5-r15-validation-ca.pem
[[ -s $run_dir/original-acl.txt ]]
[[ $(rpm -q --qf '%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}' admiral-common) == '5:0.0.1rc6-15.el10.noarch' ]]
rm -f -- "$dropin"
systemctl daemon-reload
# Reset Caddy's in-memory Admin API config before deleting its temporary cert.
systemctl restart caddy
systemctl restart admirald
for unit in caddy admirald; do
    for _ in {1..30}; do
        [[ $(systemctl show -p ActiveState --value "$unit") == active && \
           $(systemctl show -p SubState --value "$unit") == running ]] && break
        sleep 1
    done
    [[ $(systemctl show -p ActiveState --value "$unit") == active ]]
    [[ $(systemctl show -p SubState --value "$unit") == running ]]
done
setfacl -P --restore="$run_dir/original-acl.txt"
if curl --fail --silent --show-error --max-time 5 http://127.0.0.1:2019/config/ |
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert "rc6-e5-r15-validation" not in json.dumps(d)'; then
    :
else
    echo 'Caddy still references the temporary certificate; retaining it for recovery.' >&2
    exit 1
fi
rm -f -- "$ca_anchor"
update-ca-trust extract
rm -rf -- "$cert_dir" "$run_dir"
echo caddy_route_fixture_cleanup=PASS
