# Amazon Linux 2023

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
