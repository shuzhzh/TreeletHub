# TreeletHub User Guide

[← Back to README](../README.md) · [简体中文](USER_GUIDE.zh-CN.md)

## Overview

TreeletHub runs on your Mac as a **honeycomb launcher** for favorite apps and shortcuts. Pair an iPhone, iPad, or Android phone on the same Wi‑Fi to launch those Mac apps remotely. Layout stays in sync across devices.

Typical setup: leave TreeletHub running on the Mac; use your phone from another room as a remote launcher.

### Demo videos

- [Demo 1](https://youtube.com/shorts/koVxMkCqO6Q)
- [Demo 2](https://youtube.com/shorts/Z-G5ocFpQhQ)

---

## Download

| Platform | Link |
|----------|------|
| iPhone / iPad | [App Store](https://apps.apple.com/app/treelethub-%E6%95%88%E7%8E%87-%E6%8E%A7%E5%88%B6%E5%8F%B0/id6762348247) |
| Android | [Google Play](https://play.google.com/store/apps/details?id=com.treelet.treelethub) or [APK 1.3](https://github.com/shuzhzh/TreeletHub/releases/download/android-v1.3/TreeletHub-Android-1.3.apk) |
| Mac | [CDN DMG](https://models.appda.store/treelethub/TreeletHub.dmg) |

The phone app alone cannot launch Mac apps—you must install the Mac client and pair.

---

## Connect from iPhone / iPad

1. **Install the Mac app first** (website DMG), open TreeletHub on the Mac, and read the **six-digit pairing code**.
2. On iPhone, open **Connect to Mac**, enter the code, tap **Connect**.
3. Allow **Local Network** when iOS asks.

If the Mac **regenerates the pairing code**, reconnect with the **new code**.

---

## Connect from Android

1. **Install the Mac app first**, open TreeletHub on the Mac, and read the **six-digit pairing code**.
2. On Android, open **Connect to Mac**, enter the code, tap **Connect**.
3. Stay on the **same Wi‑Fi** as the Mac; allow network discovery on first use. Turn off VPN if discovery fails.

If the Mac **regenerates the pairing code**, reconnect with the **new code**.

---

## Set up the Mac honeycomb launcher

1. Tap the **+** button (or the dashed **+** on the honeycomb) to bind a `.app`, web shortcut, or system action.
2. **Pinch** to zoom, **drag** to pan; **Control-click** a tile to clear it.
3. Free plan includes up to **10** apps/shortcuts; unlock Pro once for unlimited slots.
4. Open the **gear** menu for Dynamic Island, Keyboard Launcher, language, and Pro unlock.

Compact toggles for Island / Keyboard Launcher also appear under the pairing code on the main window.

---

## After pairing (phone)

- **Apps** shows the live honeycomb launcher synced from the Mac; tap to launch.
- **Settings**: rename the device, change presets, or replace your one custom photo background.
- Use the bottom bar to switch between Apps and Settings.

### Show desktop (iPhone / Android)

On the **Apps** launcher while paired: **two-finger swipe down** hides all open Mac apps (including TreeletHub) and shows the desktop.

---

## Codex control (Android)

Put **Codex** in the launcher, then tap it on **Android** to open a control pad (Skills, scheduled tasks, settings, and so on). The Mac drives Codex with **deep links / the Codex CLI**—it does not inject keystrokes into the target app.

**ChatGPT** and **Cursor** (and every app on iPhone) only launch the matching Mac app; they no longer open a control pad.

---

## Dynamic Island on Mac (Pro)

With Pro unlocked, turn on Dynamic Island in the Mac main window or **Settings (gear)** menu. A thin strip docks at the top of the screen; hover or click to expand:

- **System apps:** an icon wall of installed Mac apps, with search and icon-size controls.
- **Workspace:** media playback, weather (WeatherKit; optional location), clipboard history, and file staging / pairing widgets.

---

## Keyboard Launcher (Mac · Pro)

With Pro unlocked, turn on **Keyboard Launcher** in the Mac main window or Settings menu:

1. When prompted, allow TreeletHub under **System Settings → Privacy & Security → Input Monitoring**.
2. **Release Control** to show the on-screen keyboard overlay; press a mapped key to launch an app, or press **Esc** / click outside to dismiss.
3. Use **Control + key** anytime to show or hide a mapped app globally—no overlay required.
4. On first enable, apps are auto-mapped by **first letter**; click empty keys to add, mapped keys to replace, and **drag** to swap assignments.

Ideal for binding Chrome, WeChat, Terminal, and other daily apps to muscle-memory keys instead of the Dock.

---

## Pro unlock (one-time purchase)

- Free: up to **10** apps/shortcuts on Mac.
- **One-time $9.99** Pro unlock (not a subscription, no auto-renewal): unlimited apps, Mac **Dynamic Island**, Mac **Keyboard Launcher**, and other Pro features.
- iOS / Mac: **App Store** in-app purchase; Mac unlock status syncs to paired phones. Android unlock follows each client’s Settings page.

---

## Permissions

| Permission | Purpose |
|------------|---------|
| Local Network | Discover Mac, sync layout, send launch commands |
| Input Monitoring (Mac, Keyboard Launcher) | Listen for Control and shortcuts to show the overlay and launch mapped apps |
| Location (optional) | Weather in Dynamic Island |
| Screen Recording (Mac, Dynamic Island) | As required by the system for island capabilities (see in-app permission guide) |

---

## Links

- [FAQ (中文)](FAQ.zh-CN.md)
- [Website](https://treelet.us/treelethub/en/)
- [Privacy](https://treelet.us/treelethub/treelet-hub-privacy.html)
- [Terms](https://treelet.us/treelethub/treelet-hub-terms.html)
