#!/bin/sh
# Runs integration_test/ on the Android emulator (CI job "Android emulator").
#
# The test "a recording shared with ACTION_SEND opens as the day" prints
# FET_WAITING_FOR_SHARE once the app is listening; this script then sends the
# app a real share, as RaceChrono would, of a file the debug build's
# TestShareProvider serves (android/app/src/debug).
#
# Some runs started the app, connected to it, and then never received a test
# result: the app's window was still Android's splash screen when the
# 15-minute limit killed it, so Flutter never presented a frame. Each attempt
# (build and tests) stops after 15 minutes; one that connected but never
# reached the share test runs once more; any other failure fails the job at
# once with the tool log and the device log.
set -u

# Sends the share once the test asks for it, until the test run ends.
share_when_asked() {
  while kill -0 "$1" 2>/dev/null; do
    if adb logcat -d -s flutter:I | grep -q FET_WAITING_FOR_SHARE; then
      echo "Sending ACTION_SEND to the app"
      # No URI grant flags: MainActivity runs in the provider's own app, so
      # it may read the URI without one (a grant flag would fail the send).
      adb shell am start -a android.intent.action.SEND \
        -t application/octet-stream \
        --eu android.intent.extra.STREAM \
        content://com.flappedear.telemetry.testshare/shared.vbo \
        -n com.flappedear.telemetry/.MainActivity \
        || echo "::warning::am start could not send the share"
      return
    fi
    sleep 2
  done
}

for attempt in 1 2; do
  status=0
  adb logcat -c
  timeout 900 flutter test integration_test -d emulator-5554 -v \
    --dart-define=SHARE_TEST=true > integration.log 2>&1 &
  test_pid=$!
  share_when_asked "$test_pid" > share.log 2>&1 &
  wait "$test_pid" || status=$?
  wait
  cat share.log
  if [ "$status" -eq 0 ]; then
    tail -n 40 integration.log
    exit 0
  fi
  if [ "$attempt" -eq 1 ] && [ "$status" -eq 124 ] \
    && grep -q 'now awaiting test result' integration.log \
    && ! grep -q 'FET_WAITING_FOR_SHARE' integration.log; then
    echo "::warning::The app connected but sent no test result (attempt $attempt); running it again."
    adb logcat -d | grep -i -E 'flutter|impeller|splash' | tail -n 60
    continue
  fi
  tail -n 300 integration.log
  adb logcat -d | tail -n 300
  exit "$status"
done
