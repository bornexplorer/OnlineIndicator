<p align="center">
  <img src=".github/assets/app-icon.png" alt="Online Indicator" width="120" />
</p>

<h1 align="center">Online Indicator</h1>

<p align="center">
A macOS menu bar app that replaces the Wi-Fi icon with customizable status indicators.
</p>
<br>
<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/platform-macOS-lightgrey?logo=apple&style=flat&color=%23FF5C60"></a>
  <a href="https://github.com/bornexplorer/OnlineIndicator/releases" target="_blank"><img src="https://img.shields.io/github/v/release/bornexplorer/OnlineIndicator?style=flat&color=%23FAC800"></a>
  <a href="https://github.com/bornexplorer/OnlineIndicator/blob/main/LICENSE" target="_blank"><img src="https://img.shields.io/github/license/bornexplorer/OnlineIndicator?style=flat&color=%2334C759"></a>
  <a href="https://ko-fi.com/bornexplorer" target="_blank"><img src="https://img.shields.io/badge/Ko--fi-FF5E5B?logo=ko-fi&logoColor=white"></a>
</p>
<br>



<img src=".github/assets/app-preview.png" alt="Online Indicator Preview" width="100%" />

## Why Online Indicator?

The macOS WiFi icon only shows that you are connected to a router, not whether your internet is actually working or being blocked. Online Indicator replaces it with a live status icon that verifies real internet connectivity at the network level, so you can instantly see if you are online, offline, or blocked without opening any apps, giving you a smarter and slightly geekier way to understand your connection at a glance.

<br>

## Features

🛜 **Ditch the boring Wi-Fi icon** <br>
Online Indicator brings a smarter network experience to your menu bar with one live status icon that clearly shows your connection and gives you quick access to Wi Fi controls and settings.

🎨 **Make it yours** <br>
Choose from 17 ready made Icon Sets or use any SF Symbol, set custom colors and labels for each state, and save your setup as your own Icon Set to switch anytime with a single tap.

📡 **Flexible monitoring** <br>
Choose any URL to ping and set the check frequency from every 30 seconds to once an hour, or tweak it to your liking.

👀 **Quick IP peek** <br>
Your IPv4 and IPv6 are always one click away in the menu. Tap to copy instantly, or hide them for a cleaner look.

<br>

## Download & Install

### 1 · Download
Head to the [**Latest Release**](../../releases/latest) page and grab the latest `.dmg` file.

### 2 · Install
Open the `.dmg` and drag **Online Indicator** into your **Applications** folder. Done.

### 3 · First Launch

#### Option A — System Settings

1. Go to **System Settings → Privacy & Security**
2. Scroll down until you see Online Indicator listed as blocked
3. Click **Open Anyway** and enter your password

#### Option B — Terminal

Paste this into Terminal and press Enter:
```bash
xattr -dr com.apple.quarantine /Applications/Online\ Indicator.app
```
Then open the app normally.

> 💡 **Why does this happen?**
> Apple requires a $99/year developer certificate to "notarise" apps. Online Indicator is free and independent, so it skips that. The warning is Apple's way of flagging uncertified apps, not a sign that anything is wrong.

<br>

## Privacy Policy

Online Indicator collects no data. Period.

- No analytics, crash reporting or usage tracking
- No personal information collected or transmitted
- All preferences are stored locally on your Mac

The only outbound network request the app makes is the connectivity probe, a simple HTTP request to `captive.apple.com` (or your custom URL) to check if the internet is reachable. This is identical to what macOS itself does internally.

<br>

## License

[MIT License](LICENSE)
