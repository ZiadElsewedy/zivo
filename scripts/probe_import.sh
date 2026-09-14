#!/usr/bin/env bash
# Times ONE real aiImportWorkoutPlan against the LOCAL emulator, bypassing
# Flutter and using a text description (no PDF). Answers "is Claude/the emulator
# the 2-minute cost, or is it the client transport?" and whether streaming vs
# buffered behaves differently.
#
# Prereqs: the emulator suite must be running (Auth 9099, Functions 5001,
# Firestore 8080) and ANTHROPIC_API_KEY must be available to the Functions
# emulator. Makes ONE real Anthropic call and spends one import quota per run.
#
# Usage:  bash scripts/probe_import.sh
set -uo pipefail

HOST=127.0.0.1
PROJECT=zivo-63f15
REGION=us-central1
FN="http://$HOST:5001/$PROJECT/$REGION/aiImportWorkoutPlan"
AUTH="http://$HOST:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key"

echo "== checking emulator reachability =="
for p in 9099 5001 8080; do
  c=$(curl -s -o /dev/null -m 2 -w "%{http_code}" "http://$HOST:$p/" 2>/dev/null)
  echo "  port $p -> $c"
  if [ "$c" = "000" ]; then
    echo "!! nothing on $p — start the emulator (firebase emulators:start) first."
    exit 1
  fi
done

echo "== minting an emulator auth token =="
ID=$(curl -s -X POST "$AUTH" -H 'Content-Type: application/json' \
  -d '{"returnSecureToken":true}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('idToken',''))")
[ -z "$ID" ] && { echo "!! could not mint idToken"; exit 1; }
echo "  ok (${#ID} chars)"

DESC='Push day: Bench press 3x8, Incline dumbbell press 3x10, Cable fly 3x15. Pull day: Deadlift 3x5, Barbell row 3x8, Lat pulldown 3x12. Legs: Back squat 3x5, Leg press 3x12, Calf raise 4x15.'

run_buffered () {
  local exec="$1"
  local body
  body=$(python3 -c "import json,sys; print(json.dumps({'data':{'text':sys.argv[1],'executionId':sys.argv[2]}}))" "$DESC" "$exec")
  echo "-- buffered POST (executionId=$exec) --"
  date "+   start %H:%M:%S.%3N"
  curl -s -o /tmp/probe_out.json \
    -w "   http=%{http_code} time_total=%{time_total}s ttfb=%{time_starttransfer}s\n" \
    -X POST "$FN" -H "Authorization: Bearer $ID" -H 'Content-Type: application/json' \
    --max-time 300 -d "$body"
  date "+   end   %H:%M:%S.%3N"
  echo "   response head: $(head -c 300 /tmp/probe_out.json)"
}

run_stream () {
  local exec="$1"
  local body
  body=$(python3 -c "import json,sys; print(json.dumps({'data':{'text':sys.argv[1],'executionId':sys.argv[2],'acceptsStreaming':True}}))" "$DESC" "$exec")
  echo "-- streaming POST (Accept: text/event-stream, executionId=$exec) --"
  date "+   start %H:%M:%S.%3N"
  curl -N -s \
    -w "\n   [stream closed] http=%{http_code} time_total=%{time_total}s\n" \
    -X POST "$FN" -H "Authorization: Bearer $ID" -H 'Content-Type: application/json' \
    -H 'Accept: text/event-stream' --max-time 300 -d "$body" \
    | sed 's/^/   sse> /' | head -60
  date "+   end   %H:%M:%S.%3N"
}

E="probe-$(date +%s)"
echo; echo "== 1) buffered .call() (the reliable transport) =="
run_buffered "$E"

echo; echo "== 2) same executionId again → should be an instant dedup hit =="
run_buffered "$E"

echo; echo "== 3) streaming attempt (does the emulator actually stream chunks?) =="
run_stream "probe-stream-$(date +%s)"

echo; echo "Now check the Functions emulator log for the matching aiImportWorkoutPlan"
echo "lines — each carries preModelMs / modelTtftMs / modelMs / totalMs."
