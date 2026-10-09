#!/usr/bin/env bash
# Prints the SHA-256 (lower-case hex) of the certificate in a keystore (alias
# androiddebugkey, password android). Usage: keystore-cert.sh KEYSTORE.
set -euo pipefail
keytool -list -v -keystore "$1" -storepass android -alias androiddebugkey 2>/dev/null \
  | sed -n 's/^.*SHA256: //p' | tr -d ':' | tr 'A-F' 'a-f'
