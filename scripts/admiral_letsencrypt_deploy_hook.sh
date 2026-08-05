#!/usr/bin/env bash
set -Eeuo pipefail

die() {
    echo "admiral-letsencrypt-deploy-hook: $*" >&2
    exit 1
}

restore_previous_pair() {
    local restored=0
    if [[ -n "${backup_cert:-}" && -f "$backup_cert" ]]; then
        mv -f -- "$backup_cert" "$deploy_dir/fullchain.pem"
        restored=1
    fi
    if [[ -n "${backup_key:-}" && -f "$backup_key" ]]; then
        mv -f -- "$backup_key" "$deploy_dir/privkey.pem"
        restored=1
    fi

    if [[ "$restored" -eq 1 ]]; then
        systemctl daemon-reload || true
        systemctl restart caddy admirald || true
    fi
}

lineage=${CERTBOT_RENEWED_LINEAGE:-}
[[ -n "$lineage" ]] || die "CERTBOT_RENEWED_LINEAGE is not set"
[[ -d "$lineage" ]] || die "certificate lineage does not exist: $lineage"

source_cert="$lineage/fullchain.pem"
source_key="$lineage/privkey.pem"
[[ -r "$source_cert" ]] || die "renewed certificate is not readable: $source_cert"
[[ -r "$source_key" ]] || die "renewed private key is not readable: $source_key"

cert_pub=$(openssl x509 -in "$source_cert" -pubkey -noout) || die "cannot parse renewed certificate"
key_pub=$(openssl pkey -in "$source_key" -pubout) || die "cannot parse renewed private key"
[[ "$cert_pub" == "$key_pub" ]] || die "renewed certificate and private key do not match"

if [[ -n "${ADMIRAL_NETWORKING_APPS_DOMAIN:-}" ]]; then
    lineage_name=$(basename "$lineage")
    escaped_apps_domain=${ADMIRAL_NETWORKING_APPS_DOMAIN//./\\.}
    if [[ ! "$lineage_name" =~ ^${escaped_apps_domain}(-[0-9]+)?$ ]]; then
        die "renewed lineage is not the expected apps-domain lineage"
    fi

    san_output=$(openssl x509 -in "$source_cert" -noout -ext subjectAltName) \
        || die "cannot read renewed certificate subject alternative names"
    apps_domain_pattern=${ADMIRAL_NETWORKING_APPS_DOMAIN//./\\.}
    probe_domain_pattern="probe.${apps_domain_pattern}"
    grep -Eq "DNS:${apps_domain_pattern}([,[:space:]]|$)" <<<"$san_output" \
        || die "renewed certificate does not cover the configured apps domain"
    if ! grep -Eq "DNS:${probe_domain_pattern}([,[:space:]]|$)" <<<"$san_output" \
        && ! grep -Eq "DNS:\\\*.${apps_domain_pattern}([,[:space:]]|$)" <<<"$san_output"; then
        die "renewed certificate does not cover the configured apps probe hostname"
    fi
fi

openssl x509 -in "$source_cert" -noout -purpose \
    | grep -Fq "SSL server : Yes" \
    || die "renewed certificate is not valid for TLS server authentication"

deploy_dir=${ADMIRAL_LETSENCRYPT_DEPLOY_DIR:-/etc/admiral/tls/letsencrypt}
install -d -o root -g caddy -m 0750 "$deploy_dir"

tmp_cert=$(mktemp "$deploy_dir/fullchain.pem.XXXXXX")
tmp_key=$(mktemp "$deploy_dir/privkey.pem.XXXXXX")
backup_cert=""
backup_key=""
if [[ -f "$deploy_dir/fullchain.pem" ]]; then
    backup_cert=$(mktemp "$deploy_dir/fullchain.pem.bak.XXXXXX")
    install -o root -g caddy -m 0644 "$deploy_dir/fullchain.pem" "$backup_cert"
fi
if [[ -f "$deploy_dir/privkey.pem" ]]; then
    backup_key=$(mktemp "$deploy_dir/privkey.pem.bak.XXXXXX")
    install -o root -g caddy -m 0640 "$deploy_dir/privkey.pem" "$backup_key"
fi

cleanup() {
    rm -f -- "$tmp_cert" "$tmp_key"
    [[ -n "$backup_cert" ]] && rm -f -- "$backup_cert"
    [[ -n "$backup_key" ]] && rm -f -- "$backup_key"
}
trap cleanup EXIT

install -o root -g caddy -m 0644 "$source_cert" "$tmp_cert"
install -o root -g caddy -m 0640 "$source_key" "$tmp_key"
mv -f -- "$tmp_cert" "$deploy_dir/fullchain.pem"
mv -f -- "$tmp_key" "$deploy_dir/privkey.pem"

if ! systemctl daemon-reload \
    || ! systemctl restart caddy admirald \
    || ! systemctl is-active --quiet caddy \
    || ! systemctl is-active --quiet admirald; then
    restore_previous_pair
    die "service restart failed after renewal; previous certificate pair restored"
fi

if [[ -n "${ADMIRAL_RENEWAL_HEALTHCHECK_URL:-}" ]]; then
    command -v curl >/dev/null 2>&1 || die "curl is required for ADMIRAL_RENEWAL_HEALTHCHECK_URL"
    curl --fail --silent --show-error --max-time 15 \
        "$ADMIRAL_RENEWAL_HEALTHCHECK_URL" >/dev/null \
        || die "renewal healthcheck failed"
fi

trap - EXIT
cleanup

echo "admiral-letsencrypt-deploy-hook: renewed certificate deployed and services healthy"
