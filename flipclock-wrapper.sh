#!/bin/bash

# Don't launch if audio is playing
AUDIO_RUNNING=$(pactl list sinks 2>/dev/null | grep -c "State: RUNNING")
if [ "$AUDIO_RUNNING" -gt 0 ]; then
    exit 0
fi

flipclock &
FPID=$!

sleep 2

DEVICES=()
for dev in /dev/input/event*; do
    [ -r "$dev" ] && DEVICES+=("$dev")
done

MONITOR_PIDS=()
for dev in "${DEVICES[@]}"; do
    (
        dd if="$dev" bs=24 count=1 status=none 2>/dev/null
        kill $FPID 2>/dev/null
    ) &
    MONITOR_PIDS+=($!)
done

wait $FPID 2>/dev/null

for pid in "${MONITOR_PIDS[@]}"; do
    kill "$pid" 2>/dev/null
done
