#!/bin/bash
# System + AUR updater for desktop login
# Downloads first (safe to interrupt), then asks for confirmation before installing

konsole -e bash -c "
echo '=== Step 1/2: Downloading updates — safe to Ctrl+C at any point ==='
yay -Syuw
DOWNLOAD_STATUS=\$?

if [ \$DOWNLOAD_STATUS -ne 0 ]; then
    echo ''
    echo '!!! Download step failed or was cancelled. Nothing was installed. !!!'
    notify-send 'Update Failed' 'Download step failed or was cancelled.' -i dialog-error -u normal -t 10000
    read -p 'Press Enter to close...'
    exit 1
fi

echo ''
echo '=== Download complete. Waiting for your confirmation to install... ==='

# Play alert sound (confirm-section only)
if command -v canberra-play &>/dev/null; then
    canberra-play --id='dialog-warning' &
elif command -v paplay &>/dev/null && [ -f /usr/share/sounds/ocean/stereo/battery-caution.oga ]; then
    paplay /usr/share/sounds/ocean/stereo/battery-caution.oga &
fi

# Fire desktop notification
notify-send 'Update Ready' 'Downloads complete. Waiting for confirmation to install.' \
    -i dialog-question -a 'System' -u normal -t 10000

# Confirmation dialog — blocks here until you click Yes/No
if kdialog --yesno 'Downloads finished. Proceed with installing updates now?' --title 'Confirm Install'; then
    echo ''
    echo '=== Step 2/2: Installing — DO NOT close this window or lose power now ==='
    yay -Su
    echo ''
    echo '=== Update complete. Press Enter to close ==='
    read
else
    echo ''
    echo 'Install cancelled. Packages remain downloaded in cache for later — run yay -Su manually when ready.'
    notify-send 'Install Skipped' 'Packages stay cached. Run yay -Su manually when ready.' -i dialog-information -u normal -t 8000
    read -p 'Press Enter to close...'
fi
"
