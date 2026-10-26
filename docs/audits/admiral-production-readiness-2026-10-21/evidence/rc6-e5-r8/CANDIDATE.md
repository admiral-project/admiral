# Admiral RC6 Epoch 5 Release 8 candidate

Candidate ID: `rc6-e5-r8`  
Product version: `0.0.1rc6`  
Epoch: `5`  
RPM Release: `8`  
Architecture: `x86_64`  
Build date: `2026-10-26`

R8 includes the Ansible fix for Caddy's access to the Admiral TLS CA. R7 was
invalidated after a Rocky Admin route synchronization failed with `permission
denied` while Caddy tried to read `/etc/admiral/tls/ca.pem`. The fix adds only
execute ACLs for user `caddy` on `/etc/admiral` and `/etc/admiral/tls` for
Single/Admin install profiles. The regression is in
`scripts/test_installer_modes.py`.

## Source pins

- Admiral common/root product source: `7fe5c9e69c2673747676e27cd134e0d69d3ebc51`
- `admirald`: `6e4a725d30c0fff877fe2252e843fae687810ae6`
- `admiral-fleet`: `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`
- `admiralctl`: `fa2a65e866310bd82bea78859804b6c3aea7989a`
- `admiral-flagship`: `b7325bbc71fc474a521496e593b2967e4d555ac1`
- `admiral-harbor`: `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`

Before both distro builds, each submodule's latest `origin/main` was fetched
and compared with the selected pin. All five current component main commits
equal their selected pins. `python3 scripts/validate-release-refs.py` passed.
The RPM metadata/pin commit is
`061420b11cfd25632b654cf93946ba6e6366e2d9`; later harness-only defaults are
in `50dfc0c1b6b2a55120df29b31283173d0fbec371` and do not change package input.

## Native builds

- EL10: Rocky Linux 10.2 x86_64, Go 1.26.10, RPM 4.19.1.1. All six RPMs built
  with `%check`; Harbor passed 352 tests. See `el10/build-environment.txt` and
  `el10/rpmbuild.log`.
- Fedora: Fedora Linux 46 Rawhide x86_64, Go 1.27.3-X:nodwarf5, RPM 6.1.0.
  All six RPMs built natively with `.fc46` dist tags; Harbor passed 352 tests.
  See `fedora/build-environment.txt` and `fedora-rpmbuild.log`.
- Fedora used its own source build and `.fc46` RPMs. No EL10 RPM was installed
  or force-installed on Fedora.

## Package identity

`el10/RPM-MANIFEST.tsv` and `fedora/RPM-MANIFEST.tsv` record all six NEVRAs and
post-signing SHA-256 values. Every Admiral package is at Epoch 5, Release 8.
`repo-signature.log` records signature verification for all RPMs and signed
repository metadata. The validation signing key fingerprint is
`8D2E8FC99FB218979157C5DBFCC63E30ED44F66E`.

The signed local repos remain available under
`/var/lib/libvirt/images/admiral-validation/repo/rc6-e5-r8/`.

## CI status

- Root `admiral` run `40381120404` passed on `50dfc0c1b6b2a55120df29b31283173d0fbec371`.
- Component repositories are green on their pinned main commits: `admirald`
  run `40263188438`; `admiral-fleet` run `40069777965`; `admiralctl` run
  `40030034925`; `admiral-flagship` run `39795263415`; `admiral-harbor` run
  `40171847383`.

R8 is built and signed but is not yet the final release candidate. No matrix
cell has been claimed on R8 at this point.
