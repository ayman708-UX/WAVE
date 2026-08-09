#!/usr/bin/env bash
# Create an Android release keystore for Stories CI signing.
# Output is written under .secrets/ (gitignored). Never commit the keystore.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS_DIR="$ROOT/.secrets"
KEYSTORE="$SECRETS_DIR/upload-keystore.jks"
CREDENTIALS="$SECRETS_DIR/keystore-credentials.env"
ALIAS="${ANDROID_KEY_ALIAS:-upload}"
VALIDITY_DAYS="${KEYSTORE_VALIDITY_DAYS:-10000}"

mkdir -p "$SECRETS_DIR"

if [[ -f "$KEYSTORE" ]]; then
  echo "error: $KEYSTORE already exists — remove it first to generate a new one" >&2
  exit 1
fi

if [[ -n "${ANDROID_KEYSTORE_PASSWORD:-}" ]]; then
  STORE_PASS="$ANDROID_KEYSTORE_PASSWORD"
  KEY_PASS="$ANDROID_KEYSTORE_PASSWORD"
elif [[ -n "${ANDROID_KEY_PASSWORD:-}" ]]; then
  STORE_PASS="$ANDROID_KEY_PASSWORD"
  KEY_PASS="$ANDROID_KEY_PASSWORD"
else
  STORE_PASS="$(openssl rand -base64 24)"
  KEY_PASS="$STORE_PASS"
fi

DNAME="${KEYSTORE_DNAME:-CN=Stories, OU=Mobile, O=PlayTorrio, C=US}"

keytool -genkeypair -v \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity "$VALIDITY_DAYS" \
  -storepass "$STORE_PASS" \
  -keypass "$KEY_PASS" \
  -dname "$DNAME"

BASE64_KEYSTORE="$(base64 -w0 "$KEYSTORE" 2>/dev/null || base64 "$KEYSTORE" | tr -d '\n')"

cat > "$CREDENTIALS" <<EOF
ANDROID_KEYSTORE_PASSWORD=$STORE_PASS
ANDROID_KEY_PASSWORD=$KEY_PASS
ANDROID_KEY_ALIAS=$ALIAS
ANDROID_KEYSTORE_BASE64=$BASE64_KEYSTORE
EOF
chmod 600 "$CREDENTIALS" "$KEYSTORE"

cat <<EOF
Created release keystore:
  Keystore:    $KEYSTORE
  Credentials: $CREDENTIALS

Add these GitHub Actions secrets on the Stories repo:
  ANDROID_KEYSTORE_BASE64
  ANDROID_KEYSTORE_PASSWORD
  ANDROID_KEY_PASSWORD
  ANDROID_KEY_ALIAS

Values are saved in $CREDENTIALS
Copy them into GitHub → Settings → Secrets and variables → Actions.

Verify:
  keytool -list -v -keystore "$KEYSTORE" -storepass '<store-password>'
EOF
