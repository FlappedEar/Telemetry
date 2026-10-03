#!/bin/sh
# Runs integration_test/ on the Android emulator (CI job "Android emulator").
#
# Some runs started the app, connected to it, and then never received a test
# result: the app's window was still Android's splash screen when the
# 15-minute limit killed it, so Flutter never presented a frame. Such an
# attempt ("now awaiting test result" without a result) stops after
# 8 minutes and runs once more; any other failure fails the job at once with
# the tool log and the device log.
set -u
for attempt in 1 2; do
  status=0
  timeout 480 flutter test integration_test -d emulator-5554 -v > integration.log 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then
    tail -n 40 integration.log
    exit 0
  fi
  if [ "$attempt" -eq 1 ] && [ "$status" -eq 124 ] \
    && grep -q 'now awaiting test result' integration.log; then
    echo "::warning::The app connected but sent no test result (attempt $attempt); running it again."
    adb logcat -d | grep -i -E 'flutter|impeller|splash' | tail -n 60
    adb logcat -c
    continue
  fi
  tail -n 300 integration.log
  adb logcat -d | tail -n 300
  exit "$status"
done
