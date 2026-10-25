# Reproduction — #201 / #257 clean dependency install

## Environment and inputs

Use fresh, updated Rocky Linux 10 x86_64 and Fedora Rawhide x86_64 guests. Enable only the distribution repositories plus Admiral COPR (Rocky also needs EPEL and CRB). Do not configure `admiral-local`. Ensure the six Admiral packages are absent. Remove the installed Flask/Mistune packages and extensions so the install transaction must resolve them again.

Use the matching six `0.0.1rc6-5` candidate RPMs for the target distribution. The exact NEVRAs and SHA-256 hashes are in `rocky/RPM-MANIFEST-el10.tsv` and `fedora/RPM-MANIFEST-fedora.tsv`. Verify all six RPM signatures with the candidate signing key before installing.

## Commands

On each guest, capture enabled repositories and available Flask/Mistune package versions:

```sh
dnf repolist --enabled
dnf repoquery --available --qf '%{name}-%{epoch}:%{version}-%{release}.%{arch} %{repoid}' python3-flask
dnf repoquery --available --qf '%{name}-%{epoch}:%{version}-%{release}.%{arch} %{repoid}' python3-mistune
```

Install all six matching candidate RPMs with signature checking and normal dependency solving enabled:

```sh
dnf install -y --setopt=localpkg_gpgcheck=1 /var/tmp/admiral-rc6-candidate/admiral-common-*.rpm /var/tmp/admiral-rc6-candidate/admiralctl-*.rpm /var/tmp/admiral-rc6-candidate/admirald-*.rpm /var/tmp/admiral-rc6-candidate/admiral-flagship-*.rpm /var/tmp/admiral-rc6-candidate/admiral-fleet-*.rpm /var/tmp/admiral-rc6-candidate/admiral-harbor-*.rpm
dnf history info last
rpm -q admiral-common admiralctl admirald admiral-flagship admiral-fleet admiral-harbor python3-flask python3-mistune
systemctl is-active admiral-harbor.service
curl -ksS -o /tmp/health.json -w '%{http_code}\n' https://127.0.0.1:5001/health
curl -ksS -o /tmp/ready.json -w '%{http_code}\n' https://127.0.0.1:5001/ready
cat /tmp/health.json /tmp/ready.json
```

Run the supported single-node installer with a disposable test SSH public key and the guest's actual hostname/IP, then repeat the service and endpoint checks. Do not publish installer logs containing generated secrets; retain a sanitized summary.

## Expected result

- DNF succeeds without `--nodeps` or disabling GPG/dependency checks.
- Flask is 3.1.3 or newer and Mistune is 3.3.0 or newer.
- All six Admiral RPMs install at the recorded candidate NEVRAs.
- Harbor is active; `/health` and `/ready` return 200, with database and admirald healthy.

## Captured evidence

The adjacent `rocky/` and `fedora/` directories contain the captured preflight, removal, repository query, signature, DNF transaction, installed NEVRA, Harbor, and sanitized installer records. `failed-harness-attempts/` preserves the non-counted first attempt for auditability.
