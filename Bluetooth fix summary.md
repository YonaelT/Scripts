# Toshiba Satellite L55DC — Bluetooth Fix Summary

**Date:** August 2026
**System:** Toshiba Satellite L55DC, AMD A10-8700P, EndeavourOS KDE, kernel 7.1.5-arch1-2
**Bluetooth adapter:** Toshiba Corp. Bluetooth Radio, USB ID `0930:0222` (Realtek RTL8723BE chip, rebadged under Toshiba's own vendor ID)

## TL;DR

Bluetooth scanned but never found any devices — transmit worked, receive didn't. Root cause: the Linux kernel's `btusb` driver has an internal table of USB IDs it grants Realtek-specific firmware handling to, and this exact Toshiba-badged chip (`0930:0222`) was simply missing from that table, even though a sibling ID (`0930:021d`) was already present. Fix: patch one line into the current `btusb.c` device table, build it as an out-of-tree module, install permanently via DKMS.

**If you have this same symptom on a `0930:0222` adapter, jump straight to [The actual fix](#the-actual-fix).**

## Table of contents

- [The symptom](#the-symptom)
- [What we ruled out (in order)](#what-we-ruled-out-in-order)
- [Root cause](#root-cause)
- [What we tried that didn't work](#what-we-tried-that-didnt-work)
- [The actual fix](#the-actual-fix)
- [Result](#result)

## The symptom

Bluetooth would not discover any devices. `bluetoothctl scan on` ran without errors, the controller reported `Discovering: yes`, and outbound HCI commands (Inquiry, LE scan) completed successfully — but zero devices were ever found, not even other phones/laptops broadcasting nearby. Bluetooth worked perfectly when booted into Windows on the same hardware, which ruled out a dead radio from the start.

## What we ruled out (in order)

1. **Basic health checks** — `rfkill` unblocked, `bluetoothd` running, adapter detected via `lsusb`. All clean.
2. **Bluetooth service accidentally disabled** — found disabled/inactive partway through (self-inflicted during an earlier frustrated moment); re-enabled and confirmed this wasn't the root cause.
3. **Raw radio TX/RX via `btmon`** — confirmed the adapter was transmitting Inquiry/LE scan requests but receiving nothing back, even at point-blank range with a device. TX healthy, RX seemingly dead.
4. **Hardware failure theory** — tested in Windows, where Bluetooth worked flawlessly. This definitively ruled out dead hardware and pointed at a Linux-side software/driver issue.
5. **USB bus noise from a failing internal webcam** — `dmesg` showed the internal webcam (`04f2:b446`) constantly disconnecting/reconnecting on the same USB controller as the Bluetooth adapter, sometimes multiple times per second. Fixed by disabling the webcam at the BIOS level (cleanest fix — cuts power at firmware level rather than fighting it in software). Bus noise eliminated, but Bluetooth still didn't work — ruled out as the sole cause.
6. **USB autosuspend / power management** — `power/control` was set to `auto`; forced to `on` to rule out the radio being suspended between operations. No change.
7. **WiFi/Bluetooth coexistence interference** — the WiFi chip (`rtl8723be`) and Bluetooth chip are the same combo silicon family, often sharing an antenna. Blocked WiFi entirely via `rfkill block wifi` to test. No change — ruled out.
8. **Missing/failed firmware loading** — checked `dmesg` for Realtek firmware load messages (none present, unlike the WiFi chip which loads firmware cleanly). Confirmed `linux-firmware` package was installed with the correct firmware files present in `/usr/lib/firmware/rtl_bt/`. Forced full USB re-enumeration (`authorized` toggle) to trigger a fresh init — still no RTL-specific firmware messages.

## Root cause

The Linux kernel's `btusb` driver matches devices against an internal table of known USB vendor/product IDs to decide which chips get vendor-specific initialization (in this case, `BTUSB_REALTEK`, which triggers the Realtek firmware-loading sequence via `btrtl`).

Toshiba ships this Realtek chip under **its own USB vendor ID** (`0930`) rather than Realtek's native one (`0bda`). Checking the current mainline kernel source confirmed that a sibling Toshiba/Realtek ID (`0930:021d`) was already in the table — but **`0930:0222` (this exact adapter) was missing**, almost certainly just an oversight that never got reported/patched upstream. Without a table entry, the adapter was only caught by a generic, class-based fallback rule that provides zero vendor-specific handling — meaning it could respond to basic HCI commands but never received the firmware needed for real Bluetooth receive functionality. This explained every symptom: TX worked, RX never did, and it worked fine in Windows because Windows uses Realtek's own proprietary driver.

## What we tried that didn't work

Before finding the real fix, we attempted to build the community `lwfinger/rtl8723au_bt` out-of-tree driver (all three of its branches: `master`, `kernel`, `new`). Every branch predated major Linux Bluetooth subsystem restructuring (`hdev->quirks` becoming a different structure, `hdev->reassembly` being removed, `HCI_AMP`/`dev_type` being deleted around 2020) and failed to compile against the modern kernel with cascading structural errors. This was correctly abandoned as too old and too risky to hand-patch.

## The actual fix

1. Pulled the **current** mainline `btusb.c` (kernel tag `v7.1`, matching the installed kernel's major.minor version) directly from the Linux kernel source — not an old fork, the real actively-maintained driver.
2. Added one line to its Realtek device table:
   ```c
   { USB_DEVICE(0x0930, 0x0222), .driver_info = BTUSB_REALTEK },
   ```
3. Downloaded the four companion header files (`btintel.h`, `btbcm.h`, `btrtl.h`, `btmtk.h`) from the same kernel version, since `btusb.c` depends on them.
4. Built `btusb.ko` as a standalone out-of-tree module against the exact installed kernel headers (no version mismatch, since it's the real current source) — compiled clean on the first real attempt.
5. Live-tested by unloading the stock module and loading the patched one (`rmmod`/`insmod`) — `dmesg` immediately showed proper RTL firmware loading (`rtl8723b_fw.bin`, `rtl8723b_config.bin`), and `bluetoothctl scan on` found nearby devices instantly. Earbuds paired and connected successfully.
6. Made it permanent via **DKMS**: packaged the patched source under `/usr/src/`, registered it with `dkms add/build/install`. DKMS placed the built module in the kernel's `/updates` path (checked before built-in modules) and will automatically rebuild it against any future kernel update — no manual reapplication needed.
7. Confirmed with a full reboot: the patched driver and correct firmware loaded completely automatically, no manual steps required.

## Result

Bluetooth is now fully functional and persistent across reboots and future kernel updates. Bonus fix along the way: the flaky internal webcam is now cleanly disabled at the BIOS level (was already something you didn't need, and it was causing background USB bus noise).

## Reproduction steps (if you have the same `0930:0222` chip)

Swap `v7.1` below for the tag matching your own `uname -r` major.minor version.

```bash
mkdir -p ~/btusb-fix && cd ~/btusb-fix

# Grab the driver source + companion headers from the matching kernel version
curl -s -o btusb.c   https://raw.githubusercontent.com/torvalds/linux/v7.1/drivers/bluetooth/btusb.c
curl -s -o btintel.h https://raw.githubusercontent.com/torvalds/linux/v7.1/drivers/bluetooth/btintel.h
curl -s -o btbcm.h   https://raw.githubusercontent.com/torvalds/linux/v7.1/drivers/bluetooth/btbcm.h
curl -s -o btrtl.h   https://raw.githubusercontent.com/torvalds/linux/v7.1/drivers/bluetooth/btrtl.h
curl -s -o btmtk.h   https://raw.githubusercontent.com/torvalds/linux/v7.1/drivers/bluetooth/btmtk.h

# Add the missing device ID (insert this line in the "Additional Realtek 8723BE" section)
sed -i '/Additional Realtek 8723BE Bluetooth devices/a\	{ USB_DEVICE(0x0930, 0x0222), .driver_info = BTUSB_REALTEK },' btusb.c
```

```makefile
# Makefile
obj-m += btusb.o
KDIR := /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
```

```bash
make
sudo systemctl stop bluetooth
sudo rmmod btusb
sudo insmod ./btusb.ko
sudo systemctl start bluetooth
bluetoothctl scan on   # should now find nearby devices
```

Once confirmed working, make it permanent with DKMS so it survives kernel updates — see the [Arch Wiki DKMS page](https://wiki.archlinux.org/title/Dynamic_Kernel_Module_Support) for the general pattern, or copy the `dkms.conf` approach from the full writeup above.
