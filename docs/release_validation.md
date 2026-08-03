# Admiral Release Validation Runbook

## 1. Purpose

This document is the authoritative execution contract for validating an Admiral release candidate.

It is intended to be executed by an autonomous validation agent on a clean EL10 x86_64 host.

The agent must:

1. identify the exact release candidate source commits;
2. build the release RPMs;
3. create isolated KVM virtual machines;
4. execute the required single-node and multi-node validation matrix;
5. collect objective evidence;
6. create GitHub issues for reproducible product defects;
7. produce a release validation report.

The agent must not modify product code, implement bug fixes, advance submodule pins, change package versions, or publish release artifacts.

## 2. Authoritative references

The agent must read these documents before executing validation:

* `docs/local_kvm_cloud_setup.md`
* `docs/multi_node_setup.md`
* the current release validation report, when one exists;
* package specifications and release-reference validation scripts;
* application definitions under `examples/apps/`.

`docs/local_kvm_cloud_setup.md` defines the supported KVM isolation model, image handling, host requirements, networking principles, and baseline security checks.

This document defines what must be executed and what constitutes PASS, FAIL, BLOCKED, or NOT TESTED.

## 3. Operating principles

### 3.1 Validate, do not repair

The validation agent must not:

* edit source code;
* apply product fixes;
* change tests to make them pass;
* update submodule commits;
* increase RPM release numbers;
* disable security controls;
* weaken assertions;
* silently work around product defects.

The agent may make temporary changes only to the validation harness or local VM infrastructure when the failure is proven to be unrelated to Admiral.

Harness changes must be documented in the report.

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

The agent must not infer that one Tier 1 operating system works because another one passed.

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

### 4.1 Primary platform

* Architecture: `x86_64`
* Operating-system family: EL10
* Virtualization: KVM/QEMU
* Security mode: SELinux `Enforcing`

### 4.2 Tier 1 operating systems

The required Tier 1 matrix is:

| Operating system | Single-node | Multi-node |
| ---------------- | ----------: | ---------: |
| CentOS Stream 10 |    Required |   Required |
| Rocky Linux 10   |    Required |   Required |
| AlmaLinux 10     |    Required |   Required |

Every operating system must use an official GenericCloud image.

The image checksum must be verified before use.

### 4.3 Deferred platforms

Architectures or operating systems outside the Tier 1 matrix must be reported as `NOT TESTED`.

Passing results from x86_64 must not be presented as evidence for aarch64.

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

If the host cannot safely run the required topology, mark validation `BLOCKED` rather than reducing VM resources below the documented minimum without disclosure.

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

For each operating system:

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

Execute the supported single-node installation procedure on each Tier 1 operating system.

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

For each Tier 1 operating system, create:

* one admin VM;
* one dedicated portal VM;
* one worker VM.

Each VM must have:

* package-installation connectivity;
* a private shared laboratory network;
* isolated persistent storage;
* a unique SSH host key;
* a verified SSH fingerprint.

### 10.1 Role installation

Execute the supported installation for:

* `--admin-node`;
* `--portal-node`;
* `--worker-node`.

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
* portal registration;
* worker registration;
* Harbor-to-admirald communication through the intended private path;
* final `admiralctl nodes list` output.

The portal and worker must appear as:

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

The agent is not authorized to:

* push source-code changes;
* modify product code;
* open bug-fix pull requests;
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
* Tier 1 matrix;
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
* all required Tier 1 single-node scenarios passed;
* all required Tier 1 multi-node scenarios passed;
* the golden lifecycle passed;
* full database and volume restore passed;
* no open blocker exists;
* all environments were cleaned up.

Use `PASS WITH KNOWN ISSUES` when all release gates pass but documented non-blocking defects remain.

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

The agent's final response must contain only:

1. overall verdict;
2. completed validation matrix;
3. failed or blocked scenarios;
4. GitHub issues created or updated;
5. path to the validation report;
6. confirmation that all VMs and temporary resources were removed.

The agent must not claim success for tests it did not execute.
