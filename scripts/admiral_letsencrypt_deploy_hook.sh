#!/usr/bin/env bash
set -Eeuo pipefail

die() {
    echo "admiral-letsencrypt-deploy-hook: $*" >&2
    exit 1
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

deploy_dir=${ADMIRAL_LETSENCRYPT_DEPLOY_DIR:-/etc/admiral/tls/letsencrypt}
install -d -o root -g caddy -m 0750 "$deploy_dir"

tmp_cert=$(mktemp "$deploy_dir/fullchain.pem.XXXXXX")
tmp_key=$(mktemp "$deploy_dir/privkey.pem.XXXXXX")
cleanup() {
    rm -f -- "$tmp_cert" "$tmp_key"
}
trap cleanup EXIT

install -o root -g caddy -m 0644 "$source_cert" "$tmp_cert"
install -o root -g caddy -m 0640 "$source_key" "$tmp_key"
mv -f -- "$tmp_cert" "$deploy_dir/fullchain.pem"
mv -f -- "$tmp_key" "$deploy_dir/privkey.pem"
trap - EXIT

systemctl daemon-reload
systemctl restart caddy admirald
systemctl is-active --quiet caddy || die "caddy is not active after renewal"
systemctl is-active --quiet admirald || die "admirald is not active after renewal"

if [[ -n "${ADMIRAL_RENEWAL_HEALTHCHECK_URL:-}" ]]; then
    command -v curl >/dev/null 2>&1 || die "curl is required for ADMIRAL_RENEWAL_HEALTHCHECK_URL"
    curl --fail --silent --show-error --max-time 15 \
        "$ADMIRAL_RENEWAL_HEALTHCHECK_URL" >/dev/null \
        || die "renewal healthcheck failed: $ADMIRAL_RENEWAL_HEALTHCHECK_URL"
fi

echo "admiral-letsencrypt-deploy-hook: renewed certificate deployed and services healthy"
