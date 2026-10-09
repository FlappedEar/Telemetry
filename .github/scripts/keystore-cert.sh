#!/usr/bin/env bash
# Prints the SHA-256 (lower-case hex) of the certificate in a keystore (alias
# androiddebugkey, password android). Usage: keystore-cert.sh KEYSTORE.
set -euo pipefail
sha=$(keytool -list -v -keystore "$1" -storepass android -alias androiddebugkey 2>/dev/null \
  | sed -n 's/^.*SHA256: //p' | tr -d ':' | tr 'A-F' 'a-f') || true
[ -n "$sha" ] || { echo "::error::Cannot read the certificate of $1." >&2; exit 1; }
printf '%s\n' "$sha"
