#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo 'run this cleanup as root on Admin' >&2; exit 2; }

domain='portal.r26.test'
run_dir=/var/tmp/rc6-e5-r26-caddy-fixture
cert_dir=/etc/caddy/rc6-e5-r26-validation
dropin=/etc/systemd/system/admirald.service.d/90-rc6-e5-r26-validation.conf
ca_anchor=/etc/pki/ca-trust/source/anchors/rc6-e5-r26-validation-ca.pem

[[ -s $run_dir/original-acl.txt ]]
[[ -f $dropin && -d $cert_dir && -f $ca_anchor ]]
grep -Fq "ADMIRAL_NETWORKING_PORTAL_HOSTNAME=$domain" "$dropin"

rm -f -- "$dropin"
systemctl daemon-reload
# Reset the dynamic Caddy API config before removing the temporary certificate.
systemctl restart caddy
systemctl restart admirald
systemctl is-active --quiet caddy
systemctl is-active --quiet admirald

setfacl -P --restore="$run_dir/original-acl.txt"
rm -f -- "$ca_anchor"
update-ca-trust extract
rm -rf -- "$cert_dir" "$run_dir"

if curl --fail --silent --max-time 5 http://127.0.0.1:2019/config/ |
   DOMAIN="$domain" CERT='/etc/caddy/rc6-e5-r26-validation/fullchain.pem' python3 -c '
import json, os, sys
text=json.dumps(json.load(sys.stdin))
assert os.environ["DOMAIN"] not in text
assert os.environ["CERT"] not in text
'; then
    :
else
    echo 'Caddy still references the temporary validation route or certificate' >&2
    exit 1
fi

[[ ! -e $dropin && ! -e $cert_dir && ! -e $ca_anchor && ! -e $run_dir ]]
printf 'caddy_fixture=REMOVED\n'
printf 'admirald=%s\n' "$(systemctl is-active admirald)"
printf 'caddy=%s\n' "$(systemctl is-active caddy)"
