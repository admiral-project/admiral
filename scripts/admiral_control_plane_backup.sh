#!/usr/bin/env bash
# SPDX-FileCopyrightText: William Moreno Reyes CP | MBA
# SPDX-License-Identifier: Apache-2.0

# Create an encrypted, off-host recovery backup of the Admiral control plane.
# The active workload S3 configuration is read from PostgreSQL after the
# operator has configured it with admiralctl backups storage set.
set -euo pipefail

readonly SECRETS_FILE=/etc/admiral/secrets
readonly ADMIRAL_ENV=/etc/admiral/admirald.env
readonly BACKUP_DIR=/var/lib/admiral/control-plane-backups
readonly OBJECT_LOCK_DAYS=30

die() {
    printf '%s\n' "admiral-control-plane-backup: $*" >&2
    exit 1
}

secret_value() {
    local file=$1 key=$2
    awk -v key="$key" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }' "$file"
}

require_root() {
    [[ ${EUID} -eq 0 ]] || die "must run as root"
}

require_file() {
    [[ -r $1 ]] || die "required file is not readable: $1"
}

require_root
require_file "$SECRETS_FILE"
require_file "$ADMIRAL_ENV"

for command in awk curl date gpg pg_dump psql sha256sum stat tar; do
    command -v "$command" >/dev/null 2>&1 || die "required command is not installed: $command"
done

secrets_key=$(secret_value "$SECRETS_FILE" ADMIRAL_SECRETS_KEY)
postgres_password=$(secret_value "$SECRETS_FILE" ADMIRAL_POSTGRES_PASSWORD)
access_key=$(secret_value "$ADMIRAL_ENV" ADMIRAL_S3_ACCESS_KEY_ID)
secret_key=$(secret_value "$ADMIRAL_ENV" ADMIRAL_S3_SECRET_ACCESS_KEY)

[[ $secrets_key =~ ^[[:xdigit:]]{64}$ ]] || die "ADMIRAL_SECRETS_KEY is missing or invalid"
[[ -n $postgres_password ]] || die "ADMIRAL_POSTGRES_PASSWORD is missing"
[[ -n $access_key && -n $secret_key ]] || die "S3 credentials are missing from $ADMIRAL_ENV"

s3_config=$(runuser -u postgres -- psql -d admiral -At -F $'\t' -c \
    "SELECT endpoint, region, bucket, prefix, force_path_style
     FROM backup_storage_configs
     WHERE enabled = TRUE AND backend = 's3'
     ORDER BY updated_at DESC
     LIMIT 1") || die "read active S3 backup storage configuration"
[[ -n $s3_config ]] || die "no active S3 backup storage is configured; run admiralctl backups storage set first"

IFS=$'\t' read -r endpoint region bucket prefix force_path_style <<<"$s3_config"
[[ $endpoint == https://* ]] || die "control-plane backups require an HTTPS S3 endpoint"
[[ -n $region && -n $bucket ]] || die "active S3 backup storage configuration is incomplete"

install -d -m 0700 -o root -g root "$BACKUP_DIR"
work_dir=$(mktemp -d "$BACKUP_DIR/.control-plane-backup.XXXXXX")
cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT
mkdir -m 0700 "$work_dir/input" "$work_dir/gpg"
export GNUPGHOME="$work_dir/gpg"

for database in admiral admiral_queue admiral_harbor; do
    PGPASSWORD="$postgres_password" pg_dump \
        --host=127.0.0.1 \
        --username=admiral \
        --format=custom \
        --file="$work_dir/input/${database}.dump" \
        "$database" || die "dump database $database"
done

mkdir -p "$work_dir/input/etc/admiral" "$work_dir/input/etc/wireguard"
cp -a "$SECRETS_FILE" "$work_dir/input/etc/admiral/secrets"
cp -a /etc/admiral/tls "$work_dir/input/etc/admiral/tls"
cp -a /etc/admirald.ini "$work_dir/input/etc/admirald.ini"
cp -a "$ADMIRAL_ENV" "$work_dir/input/etc/admiral/admirald.env"
[[ -f /etc/admiral/flagship.env ]] && cp -a /etc/admiral/flagship.env "$work_dir/input/etc/admiral/"
[[ -f /etc/admiral/harbor.env ]] && cp -a /etc/admiral/harbor.env "$work_dir/input/etc/admiral/"
[[ -f /etc/wireguard/wg-admiral.conf ]] && cp -a /etc/wireguard/wg-admiral.conf "$work_dir/input/etc/wireguard/"

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
archive="$work_dir/control-plane-${timestamp}.tar.gz"
encrypted="$BACKUP_DIR/control-plane-${timestamp}.tar.gz.gpg"
tar -C "$work_dir/input" -czf "$archive" .
printf '%s' "$secrets_key" | gpg --batch --yes --pinentry-mode loopback \
    --passphrase-fd 0 --symmetric --cipher-algo AES256 --output "$encrypted" "$archive" \
    || die "encrypt recovery archive"
chmod 0600 "$encrypted"
sha256sum "$encrypted" >"${encrypted}.sha256"
chmod 0600 "${encrypted}.sha256"

prefix=${prefix#/}
prefix=${prefix%/}
object_key="control-plane/${timestamp}.tar.gz.gpg"
[[ -n $prefix ]] && object_key="$prefix/$object_key"
base_endpoint=${endpoint%/}
if [[ $force_path_style == "t" || $force_path_style == "true" || $base_endpoint != *"amazonaws.com"* ]]; then
    object_url="$base_endpoint/$bucket/$object_key"
else
    scheme=${base_endpoint%%://*}
    host=${base_endpoint#*://}
    object_url="$scheme://$bucket.$host/$object_key"
fi

retain_until=$(date -u -d "+${OBJECT_LOCK_DAYS} days" +%Y-%m-%dT%H:%M:%SZ) \
    || die "calculate Object Lock retention deadline"

curl --fail --silent --show-error \
    --aws-sigv4 "aws:amz:${region}:s3" \
    --user "${access_key}:${secret_key}" \
    --header "x-amz-server-side-encryption: AES256" \
    --header "x-amz-object-lock-mode: GOVERNANCE" \
    --header "x-amz-object-lock-retain-until-date: ${retain_until}" \
    --upload-file "$encrypted" \
    "$object_url" || die "upload encrypted control-plane backup to S3"

remote_length=$(curl --fail --silent --show-error --head \
    --aws-sigv4 "aws:amz:${region}:s3" \
    --user "${access_key}:${secret_key}" \
    "$object_url" | awk 'BEGIN { IGNORECASE = 1 } /^content-length:/ { print $2 }' | tr -d '\r') \
    || die "verify encrypted control-plane backup in S3"
local_length=$(stat -c %s "$encrypted")
[[ $remote_length == "$local_length" ]] || die "S3 object size does not match encrypted backup"

head_response=$(curl --fail --silent --show-error --head \
    --aws-sigv4 "aws:amz:${region}:s3" \
    --user "${access_key}:${secret_key}" \
    "$object_url") \
    || die "verify encrypted control-plane backup in S3"

object_lock_mode=$(printf '%s\n' "$head_response" | awk 'BEGIN { IGNORECASE = 1 } /^x-amz-object-lock-mode:/ { print $2 }' | tr -d '\r')
object_lock_until=$(printf '%s\n' "$head_response" | awk 'BEGIN { IGNORECASE = 1 } /^x-amz-object-lock-retain-until-date:/ { print $2 }' | tr -d '\r')
[[ $object_lock_mode == GOVERNANCE ]] || die "S3 object is not protected with Object Lock Governance"
[[ -n $object_lock_until ]] || die "S3 object has no Object Lock retention deadline"

object_lock_until_epoch=$(date -u -d "$object_lock_until" +%s 2>/dev/null) \
    || die "S3 Object Lock retention deadline is invalid"
retain_until_epoch=$(date -u -d "$retain_until" +%s) \
    || die "calculate Object Lock retention deadline"
(( object_lock_until_epoch >= retain_until_epoch )) \
    || die "S3 Object Lock retention is shorter than ${OBJECT_LOCK_DAYS} days"

printf '%s\n' "created encrypted control-plane backup: s3://${bucket}/${object_key}"
