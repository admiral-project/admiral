#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo 'run this fixture as root on the disposable Portal guest' >&2; exit 2; }
run_dir=/var/tmp/rc6-e5-r15-portal-hosts
admin_address=192.168.122.169
portal_host=portal.rc6.test
[[ ! -e $run_dir ]]
! grep -Fq "$portal_host" /etc/hosts
install -d -o root -g root -m 0700 "$run_dir"
cp -a /etc/hosts "$run_dir/hosts.original"
printf '%s %s\n' "$admin_address" "$portal_host" >>/etc/hosts
restorecon -F /etc/hosts
[[ $(getent ahostsv4 "$portal_host" | awk 'NR==1 {print $1}') == "$admin_address" ]]
printf 'portal_caddy_test_host=%s\n' "$portal_host"
printf 'admin_caddy_address=%s\n' "$admin_address"
printf 'portal_hosts_fixture=ACTIVE\n'
