#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo 'run this cleanup as root on the disposable Portal guest' >&2; exit 2; }
run_dir=/var/tmp/rc6-e5-r15-portal-hosts
[[ -f $run_dir/hosts.original ]]
install -o root -g root -m 0644 "$run_dir/hosts.original" /etc/hosts
restorecon -F /etc/hosts
! grep -Fq 'portal.rc6.test' /etc/hosts
rm -rf -- "$run_dir"
echo portal_hosts_fixture_cleanup=PASS
