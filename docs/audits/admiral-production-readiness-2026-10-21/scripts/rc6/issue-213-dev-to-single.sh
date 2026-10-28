#!/usr/bin/env bash
# Reproduce legacy self-signed leaf recovery on a disposable RC6 dev-node guest.
set -euo pipefail

[[ $# -eq 4 ]] || { echo 'usage: issue-213-dev-to-single.sh SSH_KEY KNOWN_HOSTS GUEST_IP RUN_ID' >&2; exit 2; }
key=$1 known_hosts=$2 guest_ip=$3 run_id=$4
[[ $run_id =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,30}$ ]] || { echo 'invalid run id' >&2; exit 2; }
repo_root=$(git rev-parse --show-toplevel)
release=${ADMIRAL_RC_RELEASE:-20}
epoch=${ADMIRAL_RC_EPOCH:-5}
evidence=${RC6_ISSUE_213_OUTPUT_DIR:-$repo_root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-r4-rocky-single/issue-213}
mkdir -p "$evidence"
chmod 0700 "$evidence"
log="$evidence/dev-to-single-$run_id.log"
[[ ! -e $log ]] || { echo "refusing to overwrite $log" >&2; exit 1; }
umask 077
exec > >(tee "$log") 2>&1
ssh_args=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts")
guest="validator@$guest_ip"
printf 'test=ISSUE-213 candidate=0.0.1rc6-%s.el10 epoch=%s guest=%s run_id=%s start_utc=%s\n' "$release" "$epoch" "$guest_ip" "$run_id" "$(date -u +%FT%TZ)"
ssh "${ssh_args[@]}" "$guest" sudo bash -s -- "$run_id" "$release" "$epoch" "$guest_ip" <<'REMOTE'
set -euo pipefail
run_id=$1 release=$2 epoch=$3 guest_ip=$4
run_dir="/var/tmp/admiral-issue-213-$run_id"
install -d -m 0700 "$run_dir"

printf '%s\n' '=== candidate and dev-mode precondition ==='
rpm -q admiral-common admirald admiral-fleet admiralctl admiral-flagship admiral-harbor
for package in admiral-common admirald admiral-fleet admiralctl admiral-flagship admiral-harbor; do
  rpm -q --qf '%{EPOCHNUM}:%{VERSION}-%{RELEASE}\n' "$package" | grep -qx "${epoch}:0.0.1rc6-${release}.el10"
done
systemctl show admiral.service -p Environment --value 2>/dev/null || true
admirald_env=$(systemctl show admirald.service -p Environment --value)
[[ $admirald_env == *'ADMIRAL_DEV_MODE=true'* ]]

printf '%s\n' '=== existing public leaf metadata ==='
openssl x509 -noout -issuer -subject -ext subjectAltName -in /etc/admiral/tls/admirald.pem | tee "$run_dir/prior-leaf.txt"
cp -p /etc/admiral/tls/admirald.pem "$run_dir/prior-leaf.pem"
sha256sum "$run_dir/prior-leaf.pem"

printf '%s\n' '=== install legacy self-signed leaf negative control ==='
openssl req -new -x509 -key /etc/admiral/tls/admirald-key.pem -out /etc/admiral/tls/admirald.pem -days 1 -subj /CN=localhost -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1'
chmod 0640 /etc/admiral/tls/admirald.pem
chown root:admiral /etc/admiral/tls/admirald.pem
openssl x509 -noout -issuer -subject -ext subjectAltName -in /etc/admiral/tls/admirald.pem | tee "$run_dir/self-signed-leaf.txt"
if openssl verify -CAfile /etc/admiral/tls/ca.pem -verify_ip 127.0.0.1 /etc/admiral/tls/admirald.pem >"$run_dir/negative-verify.txt" 2>&1; then
  cat "$run_dir/negative-verify.txt"
  echo 'ERROR: self-signed negative control unexpectedly verified'
  exit 1
fi
cat "$run_dir/negative-verify.txt"
echo 'negative_control_untrusted_leaf=PASS'

printf '%s\n' '=== secure dev-to-single reconvergence ==='
admiral-install --single-node --yes --validation-seed --public-ip "$guest_ip" --node-id "$(hostname -s)"

printf '%s\n' '=== resulting secure leaf and chain verification ==='
openssl x509 -noout -issuer -subject -ext subjectAltName -in /etc/admiral/tls/admirald.pem | tee "$run_dir/secure-leaf.txt"
openssl verify -CAfile /etc/admiral/tls/ca.pem -verify_ip 127.0.0.1 /etc/admiral/tls/admirald.pem | tee "$run_dir/verify-loopback.txt"
openssl verify -CAfile /etc/admiral/tls/ca.pem -verify_ip "$guest_ip" /etc/admiral/tls/admirald.pem | tee "$run_dir/verify-guest-ip.txt"
ca_subject=$(openssl x509 -noout -subject -in /etc/admiral/tls/ca.pem)
leaf_issuer=$(openssl x509 -noout -issuer -in /etc/admiral/tls/admirald.pem)
[[ ${leaf_issuer#issuer=} == "${ca_subject#subject=}" ]]
grep -q 'IP Address:127.0.0.1' "$run_dir/secure-leaf.txt"
grep -q "IP Address:$guest_ip" "$run_dir/secure-leaf.txt"

printf '%s\n' '=== secure reconciliation removes dev-only portal overrides ==='
for svc in admiral-harbor-worker.service admiral-harbor-catalog-sync.service; do
  test ! -e "/etc/systemd/system/$svc.d/dev-mode.conf"
  envval=$(systemctl show "$svc" -p Environment --value)
  printf '%s environment=%s\n' "$svc" "$envval"
  [[ $envval == *'ENV=production'* && $envval != *'ENV=development'* ]]
done

printf '%s\n' '=== authenticated TLS clients ==='
harborctl ping | tee "$run_dir/harbor-client.txt"
curl --fail --silent --show-error --cacert /etc/admiral/tls/ca.pem --connect-timeout 5 --max-time 15 -o /dev/null -w 'flagship_health_http=%{http_code}\n' https://127.0.0.1:5000/flagship/api/health | tee "$run_dir/flagship-client.txt"
grep -qx 'flagship_health_http=200' "$run_dir/flagship-client.txt"
admiralctl status >"$run_dir/admiralctl-client.txt"
cat "$run_dir/admiralctl-client.txt"
admiralctl nodes list --output json >"$run_dir/nodes.json"
python3 - "$run_dir/nodes.json" <<'PY'
import json,sys
nodes=json.load(open(sys.argv[1],encoding='utf-8'))
assert any(n.get('node_role')=='worker' and n.get('status')=='active' and n.get('health_status')=='healthy' for n in nodes),nodes
print('fleet_registration_tls_client=PASS')
PY
failed=$(systemctl --failed --no-legend --no-pager)
printf 'failed_units=%s\n' "${failed:-none}"
[[ -z $failed ]]
printf 'issue_213_negative_recovery=PASS end_utc=%s\n' "$(date -u +%FT%TZ)"
REMOTE
chmod 0600 "$log"
printf 'test=ISSUE-213 result=PASS end_utc=%s\n' "$(date -u +%FT%TZ)"
sha256sum "$log"
