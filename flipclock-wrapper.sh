#!/bin/bash
# ==============================================================================
# Script Name: flipclock-wrapper.sh
# Description: Launches the AlynxZhou flipclock as a KDE Plasma screensaver,
#              triggered by swayidle after a set period of inactivity.
# Features:    Skips launch if audio is currently playing (catches YouTube,
#              video players, music). Kills flipclock instantly on any keyboard
#              or mouse input by reading directly from /dev/input kernel events.
# Dependencies: flipclock (AlynxZhou, AUR)
#               pactl (provided by libpulse)
# ==============================================================================
# --- DEPENDENCY CHECK ---
MISSING_DEPS=()

if ! command -v flipclock &>/dev/null; then
    MISSING_DEPS+=("flipclock")
fi

if ! command -v pactl &>/dev/null; then
    MISSING_DEPS+=("libpulse")
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    if command -v notify-send &>/dev/null; then
        notify-send "Flipclock Screensaver" "Missing dependencies: ${MISSING_DEPS[*]}. Launching installer..." -i system-software-update
    fi
    konsole -e bash -c "echo '=> Installing missing components for Flipclock Screensaver...'; yay -S --needed ${MISSING_DEPS[*]}; echo '=> Setup complete! Press any key to close.'; read -n 1"
    exit 1
fi
# ----------------------------------------

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
