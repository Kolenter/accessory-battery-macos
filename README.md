# Accessory Battery for macOS

<img align="right" src="Resources/AccessoryBattery.png" alt="Accessory Battery app icon" width="88">

**English** · [Русский](README.ru.md)

Battery percentages for your keyboard, mouse, trackpad, and headphones in the macOS menu bar.

<a href="https://github.com/Kolenter/accessory-battery-macos/releases/download/v1.8.1/accessory-battery-1.8.1.dmg">
  <img src="Resources/download-dmg.png" alt="Download DMG" width="182" height="42">
</a>

[Release v1.8.1](https://github.com/Kolenter/accessory-battery-macos/releases/tag/v1.8.1) · macOS 12+ · Apple Silicon and Intel

[First launch on macOS](docs/first-launch.md)

## Screenshots

![Accessory battery levels in the macOS menu bar](screenshots/menu-bar.png)

<img src="screenshots/panel.jpg" alt="The device panel with battery levels and individual visibility switches" width="404">

## Install

Open the DMG and drag **Заряд аксессуаров** to **Applications**. That’s the name to look for in Finder or Spotlight.

The DMG uses an ad hoc signature, so macOS may ask you to allow the first launch manually.

## Use

Click the menu bar indicator to see the device list. Use the switches under **В баре** to choose what appears in the menu bar. Your choices are saved.

When macOS reports separate AirPods levels, the panel shows the left and right earbuds and gives the case its own row. The app updates about every 15 seconds. Some third-party devices only show their battery level in the manufacturer’s app.

The icon pulses blue while charging. Otherwise it turns red below 8%, or green if the device is connected and has at least 8% left.

## Build

Install Xcode Command Line Tools with Swift 6, then run this from the repository root.

```sh
./build.sh
```

The universal DMG is written to `build/`.
