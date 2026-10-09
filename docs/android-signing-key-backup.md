# The Android signing key

Every released APK is signed with one key (certificate SHA-256
`7315a93d…cc4f`, pinned in `release.yml`, `signing-key.yml` and `ci.yml`), so a new
release installs over the old one and keeps the app's days. The key is not rotated:
installed apps would refuse an APK with another certificate.

Where the key lives and who can use it:

- Only the repository secret `ANDROID_DEBUG_KEYSTORE_BASE64` (the keystore as base64).
  It is not in the repository and no Actions cache holds it. A cache can be restored
  by any pull request workflow, including one running code from a fork, so a key must
  never be cached (audit finding F01, 2026-10-09).
- `ci.yml` (pull requests and `main`) and the build job of `release.yml` sign with a
  throwaway key made for the run. Their APKs do not install over a released app; to
  update a phone, install the release APK.
- `release.yml` job "Android APK (sign)" is the only job that reads the secret. It
  runs no project code (no Flutter, Gradle or pub): it downloads the built APK, signs
  it with `apksigner` (`.github/scripts/sign-apk.sh`), checks the certificate against
  the pin and deletes the key. It runs only after the job "CI is green on this commit"
  finds a successful `ci.yml` run for the exact commit.
- `signing-key.yml` runs daily: it fails when the secret is missing or holds another
  key, and deletes Actions caches whose key starts with `android-debug-keystore`, once the secret check has passed.
- Optional hardening for the owner: move the secret into a GitHub environment
  restricted to `main` and tags, and name that environment in the sign job.

## Recreating the backup

The secret was created once (2026-10-08) from the old cache by an encrypted export workflow, since removed. To create it again, use your offline copy of the keystore:

1. `base64 -w0 debug.keystore` (macOS: `base64 -i debug.keystore | tr -d '\n'`), copy the output.
2. Settings > Secrets and variables > Actions: create or replace `ANDROID_DEBUG_KEYSTORE_BASE64` and paste.
3. Actions > "Keep the Android signing key" > Run workflow must stay green: it checks the pinned certificate.
4. Keep your own offline copy of the keystore as well (a password manager attachment): a repository secret cannot be read back.
