# Amazon Linux 2023

**Tier 3, best effort only.** Amazon Linux 2023 is not a supported Admiral
installation target because its standard repositories do not provide Podman.
This page only describes an optional repository setup for experimentation; it
is not an installation or validation procedure, and its ARM64 results do not
count as x86_64 release evidence.

Enable SPAL repo for Amazon Linux 2023:

[ec2-user ~]$ rpm -qi system-release
[ec2-user ~]$ sudo dnf install spal-release
[ec2-user ~]$ cat /etc/yum.repos.d/amazonlinux-spal.repo
[ec2-user ~]$ dnf repolist --all

repo id                       repo name                                                status
amazonlinux-spal              Amazon Linux 2023 SPAL repository                        enabled
amazonlinux-spal-source       Amazon Linux 2023 SPAL repository - Source packages      disabled
amazonlinux-spal-debuginfo    Amazon Linux 2023 SPAL repository - Debug                disabled
Installing SPAL packages

Install SPAL packages on your system by running dnf install command.

podman y caddy estan disponible en el repo SPAL para arquitectura ARM.
