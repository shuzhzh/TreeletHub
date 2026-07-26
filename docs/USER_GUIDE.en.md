# TreeletHub User Guide

[← Back to README](../README.md) · [简体中文](USER_GUIDE.zh-CN.md)

## Overview

TreeletHub arranges Mac apps in a grid on your Mac. Pair an iPhone, iPad, or Android phone on the same Wi‑Fi to launch those apps remotely. Reorder slots with drag and drop on either side.

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
| Mac | [App Store](https://apps.apple.com/app/treelethub-%E6%A1%8C%E9%9D%A2%E6%95%88%E7%8E%87%E6%8E%A7%E5%88%B6%E4%B8%AD%E5%BF%83/id6762348258) or [DMG](https://github.com/shuzhzh/TreeletHub/releases/latest/download/TreeletHub.dmg) |

---

## Connect from iPhone / iPad

1. Open TreeletHub on the Mac and read the **six-digit pairing code**.
2. On iPhone, open **Connect to Mac**, enter the code, tap **Connect**.
3. Allow **Local Network** when iOS asks.

If the Mac **regenerates the pairing code**, reconnect with the **new code**.

---

## Connect from Android

1. Open TreeletHub on the Mac and read the **six-digit pairing code**.
2. On Android, open **Connect to Mac**, enter the code, tap **Connect**.
3. Stay on the **same Wi‑Fi** as the Mac; allow network discovery on first use. Turn off VPN if discovery fails.

If the Mac **regenerates the pairing code**, reconnect with the **new code**.

---

## Set up the Mac grid

1. Tap a cell and pick a `.app` to assign.
2. Drag tiles to move or swap apps between cells.
3. Extra tabs (Apps, Apps1, …) add pages; **some require a subscription**.
4. Web shortcuts and system actions may be available depending on your Mac build.

---

## After pairing (phone)

- **Apps** shows the live grid synced from the Mac; tap to launch.
- **Settings**: rename the device, change presets, or replace your one custom photo background.
- Drag to reorder; layout syncs with the Mac.

### Show desktop (iPhone / Android)

On the **Apps** grid while paired: **two-finger swipe down** hides all open Mac apps (including TreeletHub) and shows the desktop.

### Swipe between tabs (iPhone / Android)

While paired, **swipe left or right** across hub pages (and Settings) to switch tabs, or tap the bottom bar.

---

## AI control pad (iPhone / Android · ChatGPT / Codex / Cursor)

Put ChatGPT, Codex, or Cursor into the hub grid, then tap it on your phone: instead of only launching the app, the phone opens a **control pad** for it—Agent status lights, Command Keys, a skill joystick, and the reasoning dial.

- **Codex**: approve / decline, continue in a new chat, reasoning effort, Skills.
- **ChatGPT**: new chat, push to talk, send, command menu, sidebar.
- **Cursor**: push to talk, send, chat, command palette, accept / reject changes, terminal.

Use the button in the top-right corner to **remap any key**, or restore the default layout. The Mac needs **Accessibility** and **Automation** permission for TreeletHub—without it the pad shows a warning and the keys do nothing.

### Push to talk (PTT)

1. **Hold the PTT key** on the control pad and speak—the transcript appears on the phone in real time.
2. Recognition runs **on the phone itself**. **No audio leaves the phone**; only the finished text travels over Wi‑Fi to the Mac.
3. **Release** and the text lands in the ChatGPT / Codex / Cursor composer on the Mac. Read it over, then tap **Send**.

**Double-tap PTT** within 350 ms for hands-free recording; tap once more to stop. The first time, allow **Microphone** (and **Speech Recognition** on iPhone).

---

## Dynamic Island on Mac (subscription)

With an active subscription, enable the top floating strip on Mac for media, pairing code, clipboard, synced grid, clock, and weather (WeatherKit; location + network required)—see your Mac build and permissions.

---

## Keyboard Launcher (Mac · subscription)

With an active subscription, turn on **Keyboard Launcher** in the Mac main window:

1. When prompted, allow TreeletHub under **System Settings → Privacy & Security → Input Monitoring**.
2. **Release Control** to show the on-screen keyboard overlay; press a mapped key to launch an app, or press **Esc** / click outside to dismiss.
3. Use **Control + key** anytime to show or hide a mapped app globally—no overlay required.
4. On first enable, apps in `/Applications` are auto-mapped by **first letter**; click empty keys to add, mapped keys to replace, and **drag** to swap assignments.

Ideal for binding Chrome, WeChat, Terminal, and other daily apps to muscle-memory keys instead of the Dock.

---

## Subscription

- The first **Apps** page is free.
- Subscription unlocks **extra pages**, Mac **Dynamic Island**, and Mac **Keyboard Launcher**.
- iOS / Mac: **App Store**; Android extra pages: **Google Play Pro** or an active Mac subscription when available in your region.

---

## Permissions

| Permission | Purpose |
|------------|---------|
| Local Network | Discover Mac, sync layout, send launch commands |
| Accessibility / Automation (Mac) | Launch apps, drive AI control pad keys, and insert text |
| Input Monitoring (Mac, Keyboard Launcher) | Listen for Control and shortcuts to show the overlay and launch mapped apps |
| Microphone / Speech Recognition (phone, push to talk) | Transcribe speech on-device and send the text to the Mac composer |
| Location (optional) | Weather in Dynamic Island |

---

## Links

- [FAQ (中文)](FAQ.zh-CN.md)
- [Website](https://treelet.us/treelethub/en/)
- [Privacy](https://treelet.us/treelethub/treelet-hub-privacy.html)
- [Terms](https://treelet.us/treelethub/treelet-hub-terms.html)
