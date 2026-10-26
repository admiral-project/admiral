#!/usr/bin/env bash
set -euo pipefail
expected='5:0.0.1rc6-4.el10'
actual=$(rpm -q --qf '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' admiral-common)
[[ $actual == "$expected" ]]
printf 'candidate=%s\n' "$actual"
common=$(rpm -V admiral-common 2>&1 || true)
printf 'rpm_verify_common_output_begin\n%s\nrpm_verify_common_output_end\n' "$common"
[[ -z $common ]]
harbor=$(rpm -V admiral-harbor 2>&1 || true)
printf 'rpm_verify_harbor_output_begin\n%s\nrpm_verify_harbor_output_end\n' "$harbor"
if grep -Fq '/etc/systemd/system/admiral-harbor.service.d' <<<"$harbor"; then echo 'Harbor RPM reports drop-in drift' >&2; exit 1; fi
rpm -qf /etc/systemd/system/admiral-harbor.service.d
for p in /var/lib/admiral /var/lib/admiral/instances /var/lib/admiral/backups /var/lib/admiral/restore /var/lib/admiral/tmp /etc/systemd/system/admiral-harbor.service.d; do stat -c '%n %a %U:%G' "$p"; done
printf 'issue_191_205_runtime_check=PASS\n'
