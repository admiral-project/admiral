#!/usr/bin/env bash
# Run the three Release 74 Single-Node OS lanes concurrently against fresh guests.
set -uo pipefail
umask 077
[[ $# -eq 3 ]] || { echo "usage: $0 ROCKY_IP CENTOS_IP FEDORA_IP" >&2; exit 2; }
: "${R74_SSH_KEY:?Set R74_SSH_KEY to the protected lab SSH private-key path}"
repo_root=${R74_REPO_ROOT:-$(git rev-parse --show-toplevel)}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
runtime=${R74_RUNTIME_ROOT:-"$repo_root/packaging/build/validation/rc5-r74/runtime"}
mkdir -p "$runtime/single/rocky" "$runtime/single/centos" "$runtime/single/fedora"
chmod 0700 "$runtime" "$runtime/single" "$runtime/single/rocky" "$runtime/single/centos" "$runtime/single/fedora"
for os in rocky centos fedora; do
  if compgen -G "$runtime/single/$os/*.log" >/dev/null; then
    echo "evidence already exists for $os under $runtime; choose a fresh R74_RUNTIME_ROOT" >&2
    exit 2
  fi
done

"$script_dir/run-single-lane.sh" rocky "$1" >"$runtime/single/rocky/launcher.log" 2>&1 & rocky_pid=$!
"$script_dir/run-single-lane.sh" centos "$2" >"$runtime/single/centos/launcher.log" 2>&1 & centos_pid=$!
"$script_dir/run-single-lane.sh" fedora "$3" >"$runtime/single/fedora/launcher.log" 2>&1 & fedora_pid=$!

result=0
wait "$rocky_pid" || { echo 'Rocky lane failed; inspect its retained evidence.' >&2; result=1; }
wait "$centos_pid" || { echo 'CentOS lane failed; inspect its retained evidence.' >&2; result=1; }
wait "$fedora_pid" || { echo 'Fedora lane failed; inspect its retained evidence.' >&2; result=1; }
printf 'release74_single_node_parallel_pass=%s\n' "$([[ $result == 0 ]] && echo PASS || echo FAIL)"
exit "$result"
