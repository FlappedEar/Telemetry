#!/bin/sh
# Runs integration_test/ on the Android emulator (CI job "Android emulator").
#
# The test "a recording shared with ACTION_SEND opens as the day" writes
# share-fixtures/ready in the app's cache once the app is listening (read
# with run-as, which the debug build allows); this script then sends the
# app a real share, as RaceChrono would, of a file the debug build's
# TestShareProvider serves (android/app/src/debug).
#
# Some runs started the app, connected to it, and then never received a test
# result: the app's window was still Android's splash screen, so Flutter never
# presented a frame. A healthy run finishes all tests within a minute of
# connecting, so an attempt still running 4 minutes after connecting is
# stopped (a third of runs hit this on 2026-10-04, and each waited for the
# whole 15-minute limit). Each attempt (build and tests) also stops after 15
# minutes. One that connected but never reached the share test runs again, up
# to three attempts; any other failure fails the job at once with the tool log
# and the device log.
set -u

# Seconds an attempt may run after the app connected.
STALL_LIMIT=240

# Sends the share once the test asks for it, until the test run ends.
share_when_asked() {
  while kill -0 "$1" 2>/dev/null; do
    if adb shell run-as com.flappedear.telemetry \
      test -f cache/share-fixtures/ready 2>/dev/null; then
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

for attempt in 1 2 3; do
  status=0
  stalled=0
  adb logcat -c
  # A killed attempt leaves its ready file behind, and a reinstall keeps the
  # cache: remove it so this attempt's share waits for its own test.
  adb shell run-as com.flappedear.telemetry \
    rm -f cache/share-fixtures/ready 2>/dev/null || true
  # Empty the log first, so the checks below never read the last attempt's
  # lines.
  : > integration.log
  timeout 900 flutter test integration_test -d emulator-5554 -v \
    --dart-define=SHARE_TEST=true > integration.log 2>&1 &
  test_pid=$!
  share_when_asked "$test_pid" > share.log 2>&1 &
  connected_at=
  while kill -0 "$test_pid" 2>/dev/null; do
    if [ -z "$connected_at" ] \
      && grep -q 'now awaiting test result' integration.log; then
      connected_at=$(date +%s)
    fi
    if [ -n "$connected_at" ] \
      && [ $(($(date +%s) - connected_at)) -ge "$STALL_LIMIT" ]; then
      echo "::warning::No test result ${STALL_LIMIT}s after the app connected (attempt $attempt); stopping it."
      stalled=1
      kill "$test_pid" 2>/dev/null || true
      break
    fi
    sleep 5
  done
  wait "$test_pid" || status=$?
  wait
  cat share.log
  if [ "$status" -eq 0 ]; then
    tail -n 40 integration.log
    exit 0
  fi
  if [ "$attempt" -lt 3 ] \
    && { [ "$stalled" -eq 1 ] || [ "$status" -eq 124 ]; } \
    && grep -q 'now awaiting test result' integration.log \
    && ! grep -q 'Sending ACTION_SEND' share.log; then
    echo "::warning::The app connected but sent no test result (attempt $attempt); running it again."
    adb logcat -d | grep -i -E 'flutter|impeller|splash' | tail -n 60
    continue
  fi
  tail -n 300 integration.log
  adb logcat -d | tail -n 300
  exit "$status"
done
