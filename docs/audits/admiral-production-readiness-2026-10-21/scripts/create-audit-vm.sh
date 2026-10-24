#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Create an isolated x86_64 KVM guest from an immutable, DNF-updated seed.
set -euo pipefail

usage() {
  echo "usage: $0 {fedora|rocky|alma|centos} NAME NAT_IP NAT_MAC [PRIVATE_IP PRIVATE_MAC] PUBKEY_FILE" >&2
  exit 2
}

[[ $# -eq 5 || $# -eq 7 ]] || usage
os=$1 name=$2 nat_ip=$3 nat_mac=$4
if [[ $# -eq 5 ]]; then
  private_ip= private_mac= pubkey_file=$5
else
  private_ip=$5 private_mac=$6 pubkey_file=$7
fi
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
[[ $name =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]] || { echo "invalid guest name" >&2; exit 2; }
[[ $nat_mac =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || { echo "invalid NAT MAC" >&2; exit 2; }
[[ $nat_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "invalid NAT IPv4" >&2; exit 2; }
[[ -r $pubkey_file ]] || { echo "cannot read public key file" >&2; exit 2; }
if [[ -n $private_ip || -n $private_mac ]]; then
  [[ $private_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "invalid private IPv4" >&2; exit 2; }
  [[ $private_mac =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || { echo "invalid private MAC" >&2; exit 2; }
fi

root=/var/lib/libvirt/images/admiral-validation
case "$os" in
  fedora) base="$root/seeds/Fedora-Rawhide-seed-20261024-r73-updated.x86_64.qcow2"; osinfo=fedora-rawhide ;;
  rocky)  base="$root/seeds/Rocky-10.2-seed-20261024-r73-updated.x86_64.qcow2"; osinfo=rocky10 ;;
  alma)   base="$root/seeds/AlmaLinux-10.2-seed-20261024-r73-updated.x86_64.qcow2"; osinfo=almalinux10 ;;
  centos) base="$root/seeds/CentOS-Stream-10-seed-20261024-r73-updated.x86_64.qcow2"; osinfo=centos-stream10 ;;
  *) usage ;;
esac
if [[ -n ${ADMIRAL_AUDIT_BASE_OVERRIDE:-} ]]; then
  base=$ADMIRAL_AUDIT_BASE_OVERRIDE
fi
[[ -r $base ]] || { echo "seed image not found: $base" >&2; exit 1; }
overlay="$root/overlays/$name.qcow2"
iso="$root/cloud-init/$name.iso"
seed_dir="$root/cloud-init/$name"
[[ ! -e $overlay && ! -L $overlay && ! -e $iso && ! -L $iso && ! -e $seed_dir && ! -L $seed_dir ]] || {
  echo "guest artifacts already exist: $name" >&2
  exit 1
}
! virsh dominfo "$name" >/dev/null 2>&1 || { echo "libvirt domain already exists: $name" >&2; exit 1; }

mkdir -p "$(dirname "$overlay")"
python3 "$(dirname "$0")/prepare-audit-cloud-init.py" \
  --directory "$seed_dir" --name "$name" --nat-ip "$nat_ip" --nat-mac "$nat_mac" \
  --private-ip "$private_ip" --private-mac "$private_mac" --validator-public-key "$pubkey_file"
virsh net-update default add ip-dhcp-host "<host mac='$nat_mac' name='$name' ip='$nat_ip'/>" --live --config

iso_files=(user-data meta-data)
[[ ! -f "$seed_dir/network-config" ]] || iso_files+=(network-config)
# Avoid mkisofs -r: it grants read access to every file in the ISO, including
# the private host key in cloud-init user-data. Default Rock Ridge preserves
# the 0600 source-file modes for the guest's cloud-init root process.
(cd "$seed_dir" && xorriso -as mkisofs -V CIDATA -J -o "$iso" "${iso_files[@]}")
qemu-img create -f qcow2 -F qcow2 -b "$base" "$overlay"
chown qemu:qemu "$overlay" "$iso"
chmod 0600 "$iso"
restorecon -F "$overlay" "$iso"
networks=(--network "network=default,mac=$nat_mac,model=virtio")
if [[ -n $private_ip ]]; then
  networks+=(--network "network=admiral-validation,mac=$private_mac,model=virtio")
fi
virt-install --name "$name" --memory 2048 --vcpus 2 --osinfo "$osinfo" --import \
  --disk "path=$overlay,format=qcow2,bus=virtio" \
  --disk "path=$iso,device=cdrom" "${networks[@]}" \
  --graphics none --noautoconsole
python3 "$(dirname "$0")/verify-audit-vm-lease.py" \
  --network default --mac "$nat_mac" --requested-ip "$nat_ip" --timeout 90
printf 'Created %s from %s at NAT %s%s.\n' \
  "$name" "$(basename "$base")" "$nat_ip" "${private_ip:+ and private underlay $private_ip}"
printf 'known_hosts_file=%s/known_hosts\n' "$seed_dir"
ssh-keygen -lf "$seed_dir/ssh_host_ed25519_key.pub" -E sha256
