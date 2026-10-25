# Admiral Release Validation Runbook

## 1. Purpose

This document is the authoritative execution contract for validating an Admiral release candidate.

The blocking release gate targets x86_64 guests. aarch64/ARM64 is Tier 2 and
non-blocking for an x86_64 release decision; record any ARM64 result separately.

The agent must:

1. identify the exact release candidate source commits;
2. build the release RPMs;
3. create isolated KVM virtual machines;
4. execute the required six-cell x86_64 Single-Node and Multi-Node matrix;
5. collect objective evidence;
6. create GitHub issues for reproducible product defects;
7. produce a release validation report.

The agent must inventory existing GitHub issues, identify which fixes remain
local, and implement authorized source fixes on `origin/main` before producing
the candidate. Publishing release artifacts remains outside this runbook.

## 2. Authoritative references

The agent must read these documents before executing validation:

* `docs/local_kvm_cloud_setup.md`
* `docs/multi_node_setup_v1.md`
* the current release validation report, when one exists;
* package specifications and release-reference validation scripts;
* application definitions under `examples/apps/`.

`docs/local_kvm_cloud_setup.md` defines the supported KVM isolation model, image handling, host requirements, networking principles, and baseline security checks.

This document defines what must be executed and what constitutes PASS, FAIL, BLOCKED, or NOT TESTED.

## 3. Operating principles

### 3.1 Triage, repair, and validate

For each open issue, determine whether its fix is still absent locally, already
present in the selected source, or only awaits a guest validation result. Record
that disposition and the relevant commit or evidence in the report.

When a reproducible product defect is found, record it in the matching GitHub
issue (or create one if none exists), implement an authorized fix on
`origin/main`, add or update focused regression coverage, and commit with a
`Signed-off-by` trailer. Never weaken assertions or disable security controls to
make a scenario pass. A fix creates a new candidate: rebuild all six Admiral
RPMs, increment the `Release` of each, and restart all six matrix cells on
clean VMs. Record any harness adjustment and its evidence in the report.

### 3.2 Preserve the candidate

The exact source commits and RPM artifacts under validation must remain unchanged during the run.

If a product defect requires a code change, the agent must:

1. stop the affected scenario;
2. collect evidence;
3. open a GitHub issue;
4. mark the scenario as FAIL;
5. continue with independent scenarios when safe.

A corrected build must be treated as a new release candidate and must start a new validation run.

### 3.3 Prefer empirical verification

The agent must not infer that one distribution works because another one passed.

The agent must not infer that multi-node works because single-node passed.

The agent must not infer that an operation succeeded only because an API returned success.

Where possible, the agent must verify the resulting system state directly.

Examples:

* verify the running image ID after an image update;
* verify restored data after a restore;
* verify endpoint loss during pause;
* verify cleanup after deprovision;
* verify node health from the admin node;
* verify ownership and permissions on backup artifacts.

## 4. Validation scope

### 4.1 Validation platform

* Release-blocking architecture: `x86_64`
* Release-matrix operating systems: Fedora Rawhide, Rocky Linux 10, and CentOS Stream 10
* Virtualization: KVM/QEMU; use hardware virtualization where the host supports it
* Security mode: SELinux `Enforcing`

### 4.2 Required x86_64 release matrix

The release gate is the cross product of these three operating systems and two
topologies, for six required cells:

| Operating system | Architecture | Single-node | Multi-node |
| ---------------- | ------------ | ----------: | ---------: |
| Fedora Rawhide   | x86_64       |    Required |   Required |
| Rocky Linux 10   | x86_64       |    Required |   Required |
| CentOS Stream 10 | x86_64       |    Required |   Required |

Every operating system must use an official GenericCloud image.

The image checksum must be verified before use.

The EL10 release-gate targets are Rocky Linux 10 and CentOS Stream 10.
AlmaLinux 10 remains a Tier 2 EL10-compatible target but is outside the active
matrix: the project COPR `alma+epel-10-x86_64_v2` chroot does not build the Go
RPMs ([#276](https://github.com/admiral-project/admiral/issues/276)), so its two
cells cannot be executed on the exact candidate. Never report AlmaLinux as
validated while that limitation stands; re-include it only after the limitation
is fixed and both cells pass on the exact candidate.
The installer must reject other EL major versions until their dependency,
repository and security-update behavior has been explicitly implemented and
validated. Fedora Rawhide is a Tier 2 production target and compatibility signal
for a future EL11; it does not claim EL11 support. Its two x86_64 cells are
included in this release gate.

### 4.3 ARM64 Tier 2 non-blocking track

RPM build or runtime validation on `aarch64`/ARM64 may be performed and reported
as a separate Tier 2 track. ARM64 is not part of the six-cell x86_64 release
gate: an absent or failing ARM64 result does not block an otherwise valid
x86_64 release. Do not use ARM64 evidence to satisfy an x86_64 cell, or the
reverse.

For repeated validation, clone its verified immutable seed after that seed has
completed `dnf update --refresh`; do not run a separate manual update while
preparing each overlay. The unmodified GitHub installer runs its own
`dnf -y update --refresh` before Admiral setup. Verify the seed hash, guest OS,
and SELinux state before installing Admiral. Exercise the secure production
modes; `--dev-node` is not an acceptance substitute.

For the blocking x86_64 gate, the golden candidate is the same six x86_64/noarch
Admiral RPMs, with identical SHA-256 values across all six cells. If a fix
changes any Admiral RPM payload, rebuild the coordinated six-package candidate
and restart validation on fresh VMs for all six cells. An optional ARM64
build has its own package hashes and separate report; it does not add release
gate cells. EL10-only dependency RPMs may differ from Fedora repository
contents and must be listed separately in the report.

Fedora uses DNF5. Conditional package-manager steps must preserve the EL10
behavior while using Fedora's DNF5 plugins and `dnf5-automatic.timer` where
applicable.

Secure Fedora Rawhide modes also disable LLMNR through a `systemd-resolved`
configuration drop-in when that service is present. Verify that wildcard
listeners on TCP/UDP 5355 are absent and that unicast DNS resolution still
works; keep the declared firewall and exact listener checks enabled. This
Fedora-specific resolver policy does not alter EL10 behavior.

### 4.4 Deferred platforms

Operating systems outside the three named x86_64 targets and architectures
outside the optional ARM64 Tier 2 track must be reported as `NOT TESTED`.
AlmaLinux 10 belongs to this deferred set until #276 is resolved.

## 5. Host preflight

Before building or starting VMs, record:

* host operating system and version;
* kernel version;
* CPU architecture;
* available vCPUs;
* total and available RAM;
* swap capacity;
* free disk space;
* KVM availability;
* libvirt and QEMU versions;
* current Git commit;
* current submodule commits;
* UTC timestamp.

Minimum recommended host capacity:

* 8 GiB RAM;
* 4 GiB swap;
* 50 GiB free storage;
* KVM available through `/dev/kvm`.

If the host cannot safely run the required x86_64 topology, mark validation
`BLOCKED` rather than reducing VM resources below the documented minimum
without disclosure. ARM64 emulation details belong in the separate optional
Tier 2 report.

## 6. Source integrity

The agent must:

1. initialize all submodules from the commits pinned by the superproject;
2. verify that submodule working trees are clean;
3. execute `python3 scripts/validate-release-refs.py`;
4. record every component commit;
5. confirm the corresponding component CI status;
6. stop if release references are inconsistent.

Uncommitted source changes invalidate the run unless they are exclusively generated validation evidence and are explicitly listed.

## 7. Candidate RPM build

Build the candidate using the repository-supported RPM build target.

Build the blocking release candidate for x86_64 with the selected source pins:

```bash
make rpm RPM_ARCH=x86_64
```

All six required guest scenarios use these x86_64/noarch candidate RPMs.
Record NEVRA and SHA-256 for every package. An optional ARM64 build may use
`make rpm RPM_ARCH=aarch64`; record its NEVRA/SHA-256 and validation status
separately, and do not make its absence or failure block the x86_64 gate.

Record for every Admiral RPM:

* package name;
* NEVRA;
* SHA-256;
* source commit;
* build result.

The candidate repository must contain the expected Admiral RPMs and only clearly identified local dependency RPMs.

Before installation, verify that DNF selects the candidate repository rather than COPR or another remote Admiral repository.

A build failure is a release validation FAIL.

The agent must open an issue when the failure is reproducible from a clean source checkout and supported host.

## 8. VM lifecycle

For each OS in the x86_64 release matrix:

1. download the official GenericCloud image;
2. download and verify its checksum;
3. preserve the base image as immutable;
4. create clean QCOW2 overlays;
5. create temporary SSH credentials;
6. inject only the public key through cloud-init;
7. boot using KVM;
8. wait for cloud-init completion;
9. verify the expected operating system;
10. verify SELinux is `Enforcing`;
11. verify no Admiral packages, users, state, or services exist.

VMs must not reuse disks from previous operating-system or release-candidate runs.

Temporary private keys must remain on the validation host and must not be copied into guests.

## 9. Single-node validation

Execute the supported single-node installation procedure on each of the four
x86_64 release-matrix operating systems.

### 9.1 Installation acceptance

Require:

* installer exit code `0`;
* Ansible `failed=0`;
* Ansible `unreachable=0`;
* Harbor API verification PASS;
* no failed systemd units;
* all expected Admiral services active and enabled.

### 9.2 Security and operating-system checks

Verify at minimum:

* SELinux remains `Enforcing`;
* required SELinux booleans have expected values;
* no unexplained AVC denials;
* firewalld rules match the supported installation;
* internal services bind only to expected interfaces;
* PostgreSQL is not exposed publicly;
* secrets have expected ownership and permissions;
* auditd and Fail2ban are active where required;
* clock synchronization is active;
* rootless Podman is enabled;
* `subuid` and `subgid` allocations exist;
* linger is enabled for the runtime user;
* the user systemd manager is active;
* Podman uses the expected graph root and cgroup manager.

### 9.3 Reconciliation

Run the installer a second time against the same installed candidate.

Require:

* exit code `0`;
* `failed=0`;
* `unreachable=0`;
* services remain healthy.

Record all tasks reported as changed.

Do not describe the result as strict idempotency unless unexpected changes are zero or every remaining change is explained.

## 10. Multi-node validation

For each x86_64 matrix OS, create three clean VMs:

* one admin+Harbor VM;
* two worker VMs.

Each VM must have:

* package-installation connectivity;
* a private shared laboratory network;
* isolated persistent storage;
* a unique SSH host key;
* a verified SSH fingerprint.

### 10.1 Role installation

Execute the supported installation for:

* `--admin-portal-node` on the admin VM;
* `--worker-node` on each worker VM.

Require for every role:

* exit code `0`;
* Ansible `failed=0`;
* Ansible `unreachable=0`.

### 10.2 Peer and node verification

Verify:

* WireGuard peer generation and exchange;
* expected `/32` hub-and-spoke routes;
* no unintended lateral spoke connectivity;
* authenticated communication between components;
* Harbor service and API configuration on the admin VM;
* registration of both workers;
* Harbor-to-admirald communication through the intended private path;
* final `admiralctl nodes list` output.

Both workers must appear as:

* active;
* healthy;
* enabled or schedulable according to their role.

### 10.3 Workload verification

Provision a real WordPress/MariaDB workload on the worker.

The healthcheck must target the worker's published address and must not accidentally validate an admin-node loopback endpoint.

## 11. Golden application lifecycle

Using the repository WordPress example, validate:

1. application-definition apply;
2. provision;
3. setup completion;
4. running and healthy state;
5. HTTP response;
6. rootless runtime ownership;
7. expected cgroup placement;
8. database backup;
9. volume backup;
10. checksum verification;
11. backup ownership and permissions;
12. pause;
13. endpoint unavailable while paused;
14. resume;
15. endpoint restored;
16. image update;
17. actual image ID changed after restart;
18. database restore;
19. volume restore;
20. restored application data;
21. deprovision;
22. runtime cleanup.

A successful API operation is insufficient when the resulting state can be independently checked.

## 12. Restore verification

Restore validation must use two distinct instances.

### Source instance

Create identifiable data:

* one database record or application configuration change;
* one uploaded media file;
* one marker file stored in the persistent volume.

Record expected values and hashes.

Create:

* database backup;
* volume backup.

### Destination instance

Provision and pause a clean destination instance.

Restore:

1. database backup;
2. volume backup.

Then verify:

* restore operations succeeded;
* checksums were verified;
* the application starts;
* HTTP returns the expected result;
* the database marker exists;
* uploaded media exists;
* the volume marker exists and matches its original hash;
* ownership allows the application to read and modify restored files.

Failure to restore either the database or volume means full restore is FAIL.

## 13. Image-update verification

Apply an application definition with a known image version and record:

* image reference;
* immutable image ID or digest.

Change only the image version.

Require:

* `need_restarting=true`;
* successful stop/start or supported restart flow;
* new image reference;
* new immutable image ID or digest;
* old and new IDs differ;
* workload is healthy;
* `need_restarting=false`.

State transitions alone do not prove an image update.

## 14. Failure classification

Every failed step must be classified as one of:

### PRODUCT_DEFECT

Admiral does not satisfy its documented behavior.

### HARNESS_DEFECT

The validation infrastructure is incorrect or incomplete.

Examples:

* broken VM boot configuration;
* invalid port forwarding;
* incorrect cloud-init seed;
* inaccessible local package repository caused by the harness.

### ENVIRONMENTAL_BLOCKER

An external dependency prevents validation.

Examples:

* upstream mirror unavailable;
* host lacks KVM;
* insufficient disk;
* external service outage.

### EXPECTED_LIMITATION

The behavior is explicitly outside the release scope.

The classification must be supported by evidence. The agent must not classify a failure as a harness defect merely to avoid opening a product issue.

## 15. GitHub issue policy

The agent must open a GitHub issue for each distinct reproducible `PRODUCT_DEFECT`.

The agent must search existing open and closed issues before creating a new issue.

If an equivalent open issue exists:

* do not create a duplicate;
* add the new reproduction evidence as a comment when permitted;
* reference the issue in the validation report.

If an equivalent closed issue exists and the defect reproduces on the current candidate:

* create a regression issue;
* reference the previous issue.

### 15.1 Minimum issue content

Every issue must include:

* descriptive title;
* release candidate NEVRA;
* component commits;
* operating system and version;
* topology;
* exact reproduction steps;
* expected result;
* actual result;
* operation or instance IDs;
* relevant command output;
* logs or excerpts;
* security impact, when applicable;
* cleanup status;
* reproducibility result.

### 15.2 Issue title format

Use:

```text
[RC validation][component] concise failure description
```

Examples:

```text
[RC validation][fleet] Worker registration fails on AlmaLinux 10
[RC validation][restore] Rootless volume restore fails on unmapped UID
```

### 15.3 Severity guidance

Classify defects as:

* `blocker`: prevents installation or invalidates the candidate;
* `high`: breaks a major advertised lifecycle or security capability;
* `medium`: breaks a supported operation with a viable workaround;
* `low`: limited correctness, diagnostics, documentation, or usability defect.

Use existing repository labels when available. Do not create new labels.

## 16. Agent permissions

The validation agent is authorized to:

* install host validation dependencies;
* download official VM images;
* create and remove local VMs;
* create temporary local networks;
* build RPMs;
* execute supported installers;
* provision disposable Admiral applications;
* collect logs and evidence;
* search GitHub issues;
* create GitHub issues;
* comment on existing issues with new evidence;
* write or update the release validation report.
* fix product code and tests for tracked defects on `origin/main`;
* commit and push those fixes directly to `origin/main`;

The agent is not authorized to:

* merge pull requests;
* publish RPMs;
* create release tags;
* change branch protections;
* close existing issues;
* alter production infrastructure;
* use real customer data;
* execute real billing transactions.

## 17. Evidence requirements

For every scenario record:

* UTC start and end timestamps;
* host identifier;
* guest operating system;
* topology;
* candidate package versions;
* component commits;
* commands executed;
* exit codes;
* Ansible recap;
* service states;
* operation IDs;
* instance IDs;
* backup IDs;
* checksums;
* image IDs;
* node-list output;
* HTTP results;
* cleanup results;
* issue references.

Secrets, tokens, private keys, passwords, and complete environment dumps must not be included.

## 18. Release report

Write the result to:

```text
<release>.validation.md
```

The report must begin with:

* candidate identity;
* validation host;
* blocking x86_64 release matrix;
* overall verdict;
* open defects;
* excluded platforms.

Use these result values:

* `PASS`
* `PASS WITH KNOWN ISSUES`
* `FAIL`
* `BLOCKED`
* `NOT TESTED`

Historical executions must be placed in a separate section or separate file and must not be mixed with current-candidate evidence.

## 19. Release verdict

A release candidate may receive `PASS` only when:

* package build passed;
* release references are consistent;
* exact component CI is green;
* all six x86_64 release cells passed: Fedora Rawhide, Rocky Linux 10 and
  CentOS Stream 10 in both topologies;
* the golden lifecycle passed;
* full database and volume restore passed;
* no open blocker exists;
* all environments were cleaned up.

Use `PASS WITH KNOWN ISSUES` when all release gates pass but documented non-blocking defects remain.

ARM64 is outside the x86_64 release gate. An ARM64 Tier 2 issue or missing ARM64
validation must be reported separately and must not change the x86_64 verdict.

Use `FAIL` when a required scenario exposes a product defect.

Use `BLOCKED` when validation cannot be completed for environmental reasons.

## 20. Cleanup

At the end of the run:

1. deprovision all test applications;
2. verify no runtime units or containers remain;
3. shut down all VMs;
4. remove overlays and temporary cloud-init media unless retained for evidence;
5. remove temporary private keys;
6. remove temporary networks;
7. confirm no VM remains running;
8. preserve only sanitized logs and validation reports.

Cleanup failure must be recorded in the report.

## 21. Final agent response

The agent's final response must state:

1. overall verdict;
2. completed validation matrix;
3. failed or blocked scenarios;
4. GitHub issues created or updated;
5. path to the validation report;
6. confirmation that all VMs and temporary resources were removed.

The agent must not claim success for tests it did not execute.
