# VPX Launcher for macOS

![VPX Launcher icon](AppIcon.png)

A lightweight native SwiftUI frontend for [Visual Pinball X](https://github.com/vpinball/vpinball) on macOS.

VPX Launcher was built for desktop Mac users who want a simple library view instead of launching `.vpx` files manually. It scans a table collection, enriches it with community metadata and artwork, audits common dependencies, and launches tables through VPinballX.

> This is an unofficial community project. It is not affiliated with the Visual Pinball project, VPS, VPinMediaDB, or the original pinball manufacturers and rights holders.

## Features

- Native SwiftUI macOS interface.
- Recursive `.vpx` library scanning with folder-based display names.
- VPS metadata matching, including manufacturer, year, type, players, themes, IPDB ID, release version, authors, and known ROM versions.
- Automatic wheel and playfield artwork from VPinMediaDB.
- Playfield previews rotated 90° clockwise for normal portrait viewing.
- Reads VPX `.info` metadata when present, including VPS/IPDB IDs and user fields.
- Supports modern VPX `medias/` artwork layouts plus legacy `Wheel/` folders.
- Per-table custom wheel artwork overrides.
- Detects common support files and folders such as PuP, FlexDMD, UltraDMD, B2S, AltSound, AltColor, Serum, VNI, music, VPReg, and local PinMAME content.
- ROM presence auditing.
- Optional [`vpxtool`](https://github.com/francisdb/vpxtool) integration for more reliable ROM-name extraction, VPX verification, and saved high scores.
- Per-table and whole-library audits.
- Temporarily hides/suppresses the macOS Dock while VPX is running and restores the previous Dock settings when VPX exits or crashes.
- Native macOS application icon.

## Requirements

- macOS 13 or later.
- Apple Command Line Tools or Xcode (`xcrun` and `swiftc`).
- A working Visual Pinball X macOS installation.
- Your own VPX tables and any required ROMs/support files.

Optional but recommended:

- [`vpxtool`](https://github.com/francisdb/vpxtool) for table verification, ROM-name extraction, and score reading.

VPX Launcher does **not** include Visual Pinball X, PinMAME ROMs, VPX tables, PuP packs, or other game assets.

## Build

Clone the repository and run:

```bash
git clone https://github.com/sean-langley/vpx-launcher-macos.git
cd vpx-launcher-macos
./build.sh
```

The app is created at:

```text
build/VPX Launcher.app
```

Launch it directly or copy it to `/Applications`.

The build script uses the active macOS SDK selected by `xcrun`. It intentionally does not force a Swift target triple, which avoids standard-library lookup problems seen with some recent Command Line Tools installations.

## First run

1. Launch **VPX Launcher**.
2. Choose the folder containing your VPX table collection.
3. Open **Settings** and verify the Visual Pinball X application path and PinMAME ROM directory.
4. If installed, confirm the detected `vpxtool` path.
5. Use **Refresh VPS** to download/update community metadata and artwork matching.
6. Use **Audit Tables** to check ROM references and, when `vpxtool` is available, VPX file structure.
7. Select a table and use **Make Table Portable** to copy its directly referenced ROM ZIP from the configured ROM folder into a table-local `pinmame/roms` folder. Existing differing files are never overwritten, and the launcher warns when clone/parent dependencies cannot be determined.

## `vpxtool` detection

VPX Launcher looks in common locations including:

```text
/opt/homebrew/bin/vpxtool
/usr/local/bin/vpxtool
~/bin/vpxtool
~/.local/bin/vpxtool
```

A different binary can be selected manually in Settings.

Without `vpxtool`, launching, VPS metadata, artwork, and the fallback ROM audit still work. VPX verification and score reading require `vpxtool`.

## Artwork priority

For wheel artwork, the launcher prefers local/user-provided media over downloaded media:

1. Custom artwork selected in VPX Launcher.
2. VPX `medias/` wheel artwork.
3. Legacy local `Wheel/` artwork.
4. Cached VPinMediaDB artwork.
5. Generic fallback icon.

## Community data sources

VPX Launcher can use these public community projects at runtime:

- [Virtual Pinball Spreadsheet database](https://github.com/VirtualPinballSpreadsheet/vps-db) — table metadata and matching IDs.
- [VPinMediaDB](https://github.com/superhac/vpinmediadb) — wheel and playfield media indexed by VPS ID.
- [`vpxtool`](https://github.com/francisdb/vpxtool) — optional local VPX inspection utilities.

The launcher does not bundle those projects. Downloaded metadata and media are cached locally.

## Local data

Runtime data is stored under normal macOS user locations:

```text
~/Library/Application Support/VPX Launcher/
~/Library/Caches/VPX Launcher/
```

The application-support directory contains persistent launcher data such as custom artwork/matches. Downloaded VPS/VPinMediaDB cache data is stored in the cache directory where appropriate.

## ROM audit limitations

The ROM audit answers whether the ROM ZIP named by a table exists in the configured ROM directory. It does not independently validate every parent/clone dependency in a split PinMAME set. PinMAME remains authoritative for the actual ROM dependency chain when a table starts.

## Current status

Version **0.3** is a small personal/community project rather than a polished commercial frontend. It has primarily been developed around current VPX Standalone/BGFX builds on Apple Silicon macOS. Bug reports and small improvements are welcome.

## License

VPX Launcher itself is released under the [MIT License](LICENSE).

Third-party projects, table files, ROMs, artwork, and other pinball assets remain subject to their own licenses and rights.
