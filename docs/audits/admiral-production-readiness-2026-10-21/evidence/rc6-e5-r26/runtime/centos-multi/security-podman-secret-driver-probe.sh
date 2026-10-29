#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
evidence_dir="$repo_root/docs/audits/admiral-production-readiness-2026-10-21/evidence/rc6-e5-r26/runtime/centos-multi"
key="/var/lib/libvirt/images/admiral-validation/keys/validator_ed25519"
known_hosts="/var/lib/libvirt/images/admiral-validation/cloud-init/rc6e5r18-ipv6-worker/known_hosts"
output="$evidence_dir/security-podman-secret-driver-20261029.log"

umask 077
{
  printf 'probe_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'candidate=RC6 E5 R26 CentOS Stream 10 x86_64 Worker\n'
  printf 'scope=effective rootless Podman secret driver; synthetic secret only\n'
  ssh -i "$key" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    -o ConnectTimeout=5 \
    -o "UserKnownHostsFile=$known_hosts" \
    validator@192.168.122.21 'sudo -n bash -s' <<'REMOTE'
set -euo pipefail

printf 'guest_os='
source /etc/os-release
printf '%s %s\n' "$ID" "$VERSION_ID"
printf 'admiral_fleet_nevra='
rpm -q --qf '%{NEVRA}\n' admiral-fleet
printf 'podman_version='
podman --version

apps_uid="$(id -u admiral-apps)"
apps_home="$(getent passwd admiral-apps | cut -d: -f6)"
runtime_dir="/run/user/$apps_uid"
podman_as_apps=(runuser -u admiral-apps -- env "HOME=$apps_home" "XDG_RUNTIME_DIR=$runtime_dir" sh -c 'cd "$HOME" && exec podman "$@"' podman)
printf 'admiral_apps_uid=%s\n' "$apps_uid"
printf 'user_manager_state='
systemctl is-active "user@$apps_uid.service" || true
printf 'rootless_info='
"${podman_as_apps[@]}" info --format 'rootless={{.Host.Security.Rootless}}'

secret_name="admiral-audit-driver-probe-$(date -u +%Y%m%d%H%M%S)"
cleanup() {
  "${podman_as_apps[@]}" secret rm "$secret_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'secret_create=synthetic_payload\n'
printf '%s' 'admiral-audit-only-marker' | "${podman_as_apps[@]}" secret create "$secret_name" - >/dev/null
driver="$("${podman_as_apps[@]}" secret inspect --format '{{.Spec.Driver.Name}}' "$secret_name")"
printf 'effective_secret_driver=%s\n' "$driver"
case "$driver" in
  file) printf 'at_rest_classification=read_protected_file_not_encrypted\n' ;;
  pass) printf 'at_rest_classification=gpg_encrypted_driver\n' ;;
  *) printf 'at_rest_classification=other_driver\n' ;;
esac

"${podman_as_apps[@]}" secret rm "$secret_name" >/dev/null
trap - EXIT
if "${podman_as_apps[@]}" secret inspect "$secret_name" >/dev/null 2>&1; then
  printf 'cleanup_verified=false\n'
  exit 1
fi
printf 'cleanup_verified=true\n'
REMOTE
} >"$output" 2>&1

cat "$output"
