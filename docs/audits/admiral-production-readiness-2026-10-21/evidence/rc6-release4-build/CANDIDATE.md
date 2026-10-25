# RC6 Release 4 local RPM build evidence

Status: both native distro builds **PASS**; this does not count as a runtime matrix cell.

- Candidate NEVR: `0.0.1rc6-4`.
- Build initiated from root `main` commit `5f0b1a6` (release packaging commit `091619f`); RPM source archive pin for the root package: `d50f8f323597140cafa1cefab69744cc56c6831f`.
- Component source pins: admirald `0fd76b6c902cfae179cfe6fb3e685c935a350cf7`; admiral-fleet `fc6909f6c41507d04aa204ebeafbbaaa4ef2c686`; admiralctl `fa2a65e866310bd82bea78859804b6c3aea7989a`; flagship `b7325bbc71fc474a521496e593b2967e4d555ac1`; harbor `dd4818b6e2bc53eea4495fc5e374a4893cfcb107`.
- EL10: native `rpmbuild` on the Rocky Linux 10.2 host; six `.el10` RPMs and six SRPMs built. `admiral-flagship` `%check`: 266 passed; `admiral-harbor` `%check`: 352 passed; Go `%check` and ELF architecture checks succeeded.
- Fedora: native `rpmbuild` in `localhost/admiral-r67-fedora-buildenv:rawhide` (Fedora Rawhide prerelease, Fedora 46 / Python 3.15); six `.fc46` RPMs and six SRPMs built. `admiral-flagship` `%check`: 266 passed; `admiral-harbor` `%check`: 352 passed; Go `%check` and ELF architecture checks succeeded.
- No EL10 binary was installed or used in Fedora. Fedora output was built natively in Fedora.
- The six packages in each build have their exact NEVRA and SHA-256 recorded in the adjacent `*-nevra.tsv` and `*-sha256.txt` manifests. Corresponding signed local repository copies have separate `signed-*-nevra.tsv` and `signed-*-sha256.txt` manifests.
- Both candidate repositories were signed with the isolated RC6 R4 lab key; RPM checksums and detached `repomd.xml` signatures verified. Local HTTP key retrieval returned HTTP 200. No signing secret is included in this repository.
- Full build transcripts are `../rc6-release4-el10-build.log` and `../rc6-release4-fedora-build.log`; their hashes are in `build-logs-sha256.txt`.

Runtime validation must use these exact six-RPM sets per OS and record package NEVRA/hash in each guest. Any source or spec change invalidates this candidate; a rebuild requires incrementing Release for all six packages.
