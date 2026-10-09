#!/usr/bin/env bash
# Signs an already built APK with a keystore, replacing the signature it has.
# Runs no project code (no Flutter, no Gradle), so the key sits beside nothing
# but apksigner. Usage: sign-apk.sh IN.apk KEYSTORE OUT.apk
# The key and store passwords are the public value "android" (a debug key).
set -euo pipefail
here=$(dirname "$0")
in=$1
keystore=$2
out=$3
apksigner=$(ls "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -n 1)
java_home="${JAVA_HOME_21_X64:-$JAVA_HOME}"
JAVA_HOME="$java_home" PATH="$java_home/bin:$PATH" "$apksigner" sign \
  --ks "$keystore" --ks-key-alias androiddebugkey \
  --ks-pass pass:android --key-pass pass:android \
  --v2-signing-enabled true --v3-signing-enabled true --v4-signing-enabled false \
  --out "$out" "$in"
expected=$("$here/keystore-cert.sh" "$keystore") || { echo "::error::Cannot read the keystore." >&2; exit 1; }
actual=$("$here/apk-cert.sh" "$out")
[ -n "$expected" ] && [ "$expected" = "$actual" ] || {
  echo "::error::The signed APK has certificate '$actual', not the key's $expected." >&2
  exit 1
}
# Android 8 (minSdk 26) needs the v2 scheme; v3 is for Android 9 and later.
verbose=$(JAVA_HOME="$java_home" PATH="$java_home/bin:$PATH" "$apksigner" verify -v "$out" 2>&1) || true
printf '%s\n' "$verbose" | grep -E '^Verified using v[0-9.]+ scheme'
for scheme in v2 v3; do
  printf '%s\n' "$verbose" | grep -Eq "^Verified using $scheme scheme.*: true" || {
    echo "::error::The signed APK is not verified with the $scheme scheme." >&2
    exit 1
  }
done
echo "Signed with certificate SHA-256: $actual"
