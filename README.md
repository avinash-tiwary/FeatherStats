# FeatherStats

FeatherStats is a tiny, native menu-bar monitor for Apple-silicon Macs. It shows CPU, unified memory, temperature, disk, and battery without a Dock icon or background helper.

## Install

1. Download `FeatherStats.dmg` from the [latest release](../../releases/latest).
2. Open the DMG and drag FeatherStats into Applications.
3. Launch FeatherStats. Its gauge appears in the menu bar.

The release is ad-hoc signed, not notarized. If macOS blocks the downloaded build, compile it locally using the instructions below. Public distribution without Gatekeeper warnings requires Apple Developer ID signing and notarization.

## Why it is lightweight

- Pure AppKit and system frameworks—no Electron, web view, dependencies, network access, analytics, or helper process.
- The release app is about 564 KiB and used a 21 MiB physical footprint in testing.
- CPU and memory refresh every 3 seconds; temperature and battery every 30 seconds; disk every 60 seconds.
- CPU load is calculated from every logical core and normalized to a system-wide 0–100%.
- Apple-silicon CPU and graphics share unified memory, so FeatherStats does not claim a misleading separate VRAM number.
- Temperature uses the local IOKit/HID sensor service with an AppleSMC and macOS thermal-state fallback.

See [PERFORMANCE.md](PERFORMANCE.md) for the resource and differential leak-test results.

## Build from source

Requires macOS 13 or newer, Apple silicon, and Xcode command-line tools.

```sh
git clone REPOSITORY_URL
cd FeatherStats
./Scripts/build_dmg.sh
```

The DMG is created at `dist/FeatherStats.dmg`.

## Test

```sh
swift test
swift run FeatherStats --snapshot
```

FeatherStats is available under the [MIT License](LICENSE).
