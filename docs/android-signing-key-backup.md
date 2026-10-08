# Backing up the Android signing key

Every release and `main` APK is signed with one key (certificate SHA-256
`7315a93d…cc4f`, pinned in `ci.yml`, `release.yml`, `signing-key.yml` and
`export-signing-key.yml`). It lives in the Actions cache `android-debug-keystore-v1`,
which `signing-key.yml` keeps alive daily. If the cache is ever lost, a copy in the
repository secret `ANDROID_DEBUG_KEYSTORE_BASE64` (the keystore as base64) is used
instead: `ci.yml`, `release.yml` and `signing-key.yml` write it to
`~/.android/debug.keystore` when the cache is empty, and the pinned-certificate checks
still refuse any other key. `signing-key.yml` also puts a key restored from the secret
back into the cache.

## One-time backup

A workflow cannot write a secret with its own token, so the key goes through the owner
once, encrypted:

1. Settings > Secrets and variables > Actions > New repository secret:
   `SIGNING_KEY_EXPORT_PASSPHRASE` = a long random passphrase only you know
   (the keystore password is the public `android`, so the passphrase is the only
   protection of the artifact, which anyone with read access can download).
2. Actions > "Export the Android signing key" > Run workflow (branch `main`).
3. Download the artifact `signing-key-encrypted` from the run (expires after one day).
4. On your computer, in the folder holding the unzipped `debug.keystore.base64.enc`,
   run `openssl version` (it must say OpenSSL 3 or LibreSSL 3.x; otherwise
   `brew install openssl` and use `$(brew --prefix openssl)/bin/openssl`), then
   `openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in debug.keystore.base64.enc -out key.b64`
   and type the passphrase when asked.
5. Check the result: `base64 -d < key.b64 > k.jks && keytool -list -keystore k.jks -storepass android -alias androiddebugkey`
   must list `androiddebugkey`; then `rm k.jks`.
6. `pbcopy < key.b64` (macOS), then create the repository secret
   `ANDROID_DEBUG_KEYSTORE_BASE64` and paste.
7. Delete `key.b64` and the encrypted file, and delete the secret
   `SIGNING_KEY_EXPORT_PASSPHRASE`.
8. Check: Actions > "Keep the Android signing key" > Run workflow stays green.

Keep your own offline copy of the keystore as well if you can (a password manager
attachment): a repository secret cannot be read back.
