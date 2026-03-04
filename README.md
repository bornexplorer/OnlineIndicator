<p align="center">
  <img src=".github/assets/app-icon.png" alt="Online Indicator" width="120" />
</p>

<h1 align="center">Online Indicator</h1>

<p align="center">
A lightweight, customisable macOS menu bar utility that replaces the default Wi-Fi icon with a color-coded status indicators giving you a clear view of your connection at a glance.
</p>
<br>
<p align="center">
  <img src="https://img.shields.io/github/v/release/bornexplorer/online_indicator?label=release&color=e05d44">
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey?logo=apple">
  <img src="https://img.shields.io/github/license/bornexplorer/online_indicator?color=44cc11">
  <!--
  <img src="https://img.shields.io/github/downloads/bornexplorer/online_indicator/total?label=downloads&color=e05d44">
  <img src="https://img.shields.io/github/stars/bornexplorer/online_indicator?color=e05d44">
  -->
</p>

<br>

## Why Online Indicator?

The macOS Wi-Fi icon only shows whether you’re connected to a router. It doesn’t tell you if your internet is actually working or if something is blocking your connection.

Online Indicator replaces it with a live status icon that checks whether your internet traffic is getting through. You can instantly see if you’re online, offline, or blocked without opening any apps.

You can also customize the icon using Apple’s SF Symbols and choose your own colors for each status, so it looks and works the way you prefer. This way, you can understand your network status at a glance.

<br>

## Features

- **Live status in the menu bar** — see at a glance if you're online, blocked, or offline
- **Three distinct states** — Connected, Blocked (network up but no internet), and No Network
- **Customisable check interval** — 30 seconds(default) or set your own
- **Custom ping URL** — test against any endpoint you choose, not just the default
- **Fully customisable icons** — choose any SF Symbol and any colour for each state
- **Optional menu bar label** — add a short text label alongside the icon
- **Local IP address display** — see your IPv4 and IPv6 addresses directly from the menu

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
