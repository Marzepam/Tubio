<img width="632" height="468" alt="Screenshot 2026-10-23 at 10 38 34" src="https://github.com/user-attachments/assets/e5127198-b9cf-4a15-bae8-9001f47d9aea" />
# Tubio

A native macOS app (SwiftUI) for downloading video from streaming sites, built as a lightweight, visual wrapper around [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://ffmpeg.org/).

## Where this project came from

The starting point was an analysis of the open-source project **Open Video Downloader** (youtube-dl-gui, by Jelle Glebbeek, licensed **AGPL-3.0-or-later**, Tauri 2 + Rust + Vue 3) — a solid, well-designed app with the same general purpose.

The first version of Tubio was deliberately *loosely* inspired by that code (its own, simpler format selection, its own mechanism for detecting the resulting file's path) — mainly out of concern for the AGPL-3.0 license, which, upon distribution/sale, would require releasing all derivative code under the same license. Since Tubio is **strictly for your own personal use** (not sold or distributed), that restriction no longer applies — AGPL governs distribution, not private compiling and use.

In this version, the download engine (format selection `-f`/`-S`, progress template, how the final file path is determined) is therefore a **faithful port** of the actual logic from that project's `src-tauri/src/runners/ytdlp_args/format_args.rs`, `output_args.rs`, and `ytdlp_runner.rs` — rewritten in Swift, not copied line-by-line from Rust (different syntax, different concurrency model), but computing the same `yt-dlp` selectors and flags, instead of a simplified version of its own that in practice behaved differently. If you ever want to share or sell this app, it's worth revisiting the licensing question — for now, with purely private use, it isn't an issue.

The icon and branding remain an original design (see below) — a separate decision, unrelated to the code's license.

## What the app does

- Paste a video URL → Tubio asks `yt-dlp -J` for metadata (title, thumbnail, duration, available resolutions) — bigger thumbnails in the queue than the first version, so a video is easier to recognize at a glance.
- Pick a quality (best / a specific resolution / audio-only as MP3) — the format selector (`-f`/`-S`) is a faithful port of what the original project actually builds for the same choice, not a simplified version of its own.
- Tubio queries `yt-dlp` with `--progress-template` for exactly the same set of fields as the original project, to get download progress in a format that's easy to parse (rather than a human-readable terminal progress bar), and shows it as a bar + speed + ETA.
- Tubio determines the final file path the same way the original project does: by watching the ordinary, plain-text lines `yt-dlp` prints anyway during its work (`[download] Destination: …`, `[Merger] Merging formats into "…"`, `[VideoRemuxer] Destination: …`, …) and remembering the one with the highest "confidence" — not through a separate `--print` flag, which in the first version was the only, not fully battle-tested, approach.
- The queue handles several downloads at once (limit set in Settings), **pause/resume** (a real `SIGSTOP`/`SIGCONT`, not just a visual one — see below), cancelling, retrying failed downloads, "Show in Finder" / "Open".
- The window is light or dark depending on the system appearance (System Settings → Appearance), without forcing one theme — the icons work the same way: every neutral (non-red) icon in the interface tracks the same system label color as the Settings gear icon (dark in Light mode, light in Dark mode).
- In Settings: checking for and installing `yt-dlp`/`ffmpeg` updates via Homebrew (see "Checking for updates" below).
- On first launch on a given machine, if `yt-dlp`/`ffmpeg` aren't installed yet, Tubio immediately shows a brief heads-up about it (see "First launch" below) — before you even try adding a link.
- The interface speaks Polish or English automatically, depending on the system language (see "App language" below) — no switch in Settings.

## What the app deliberately does **not** do

- **It doesn't download or run `yt-dlp`/`ffmpeg` for you.** Open Video Downloader has a whole system for this: a signed Ed25519 manifest, SHA-256 verification, downloading binaries from the internet. It's a serious, well-built mechanism — but also a larger attack surface (you have to trust the server serving the manifest) and more code to maintain. Tubio instead **looks for** `yt-dlp`/`ffmpeg` installed via Homebrew (`/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, `~/.local/bin`) or on `PATH`. If it can't find them, it shows a screen with a ready-to-copy `brew install yt-dlp ffmpeg`.
- **It doesn't manage any login credentials** for sites (OVD has a whole Stronghold + OS keyring module for this, since it handles cookie files/logins). Tubio deliberately leaves this alone — there's no secrets store at all, because it doesn't keep anything like that.
- **It has no Sandbox** (`App Sandbox`), unlike Movi. The Sandbox is fundamentally incompatible with locating/running arbitrary user-installed binaries from anywhere and writing to an arbitrarily chosen destination folder. The app is built for distribution outside the Mac App Store (signed + notarized), not for the Store itself.
- **It doesn't support playlists yet** — the `PlaylistInfo` model is defined but not wired up to the UI. One URL at a time, for now.
- **Pause doesn't cover ffmpeg.** "Pause" itself is real — it sends `SIGSTOP` to the `yt-dlp` process (see "Pause/resume" below) — but if the data has already moved on to a separately spawned `ffmpeg` (merging/transcoding after downloading), that process isn't frozen, since it runs as its own, independent child. In practice, pausing matters mainly during the download phase itself, which is most of a download's duration.

## Pause/resume

"Pause" on an in-progress download sends a real Unix `SIGSTOP` signal to the `yt-dlp` process — the same mechanism as `Ctrl+Z` in a terminal: the process genuinely freezes (zero CPU usage, zero transfer), not just a "fake" pause in the interface. "Resume" sends `SIGCONT` and the process continues from the same point, without losing any data already downloaded. "Cancel" on a paused download first sends `SIGCONT` (a `SIGTERM` sent to a frozen process would sit in its queue, unhandled, until it's resumed), then terminates the process normally.

The analyzed original project has **no** pause/resume feature at all (verified in its source — there's no trace of `pause`/`SIGSTOP`/`suspend` in the Rust code) — this is Tubio's own feature, added at your request, not a port of anything that already existed.

Limitation: this only freezes the `yt-dlp` process itself. If a download has already moved into the merging/transcoding phase through a separately spawned `ffmpeg`, that child process keeps running — see the note in "What the app deliberately does not do" above.

## Checking for updates (yt-dlp / ffmpeg)

Settings has a "yt-dlp / ffmpeg" section with a "Check for updates" button (runs `brew outdated --quiet yt-dlp ffmpeg` and shows both tools' current versions) and, when there's something to update, an "Update" button (`brew upgrade yt-dlp ffmpeg`).

This is an **adaptation**, not a port, of the update mechanism in the analyzed original project — and the distinction is worth understanding. The original (`binaries_manager.rs` + the `commands/updater/` module) has two completely separate systems: (1) its own yt-dlp/ffmpeg binary-update system — a signed Ed25519 manifest, SHA-256 verification, downloading from its own servers that host those binaries, and (2) an unrelated self-updating mechanism for the Tauri app itself (`tauri_plugin_updater`). Point (1) has nothing to port to: Tubio doesn't manage its own copies of yt-dlp/ffmpeg (see `BinaryLocator`) and has no binary-hosting server of its own for such a port to point at. Rather than fake a port of a system Tubio doesn't have, `HomebrewUpdater` does what you'd do by hand in Terminal anyway — it asks Homebrew, which already manages these binaries on your system.

## First launch

On the very first launch of Tubio on a given machine (remembered in `UserDefaults`, so it shows exactly once, never again) — if `yt-dlp`/`ffmpeg` aren't installed at that moment — a brief "Welcome to Tubio" alert pops up letting you know these two tools are needed for downloading video, before you even try adding a link. This is deliberately an *addition* to the existing "yt-dlp and/or ffmpeg missing" screen (`MissingToolsView`), not a replacement for it — that screen, with its ready-to-copy `brew install yt-dlp ffmpeg`, still shows up every time the tools are unavailable, for as long as they're actually missing. If `yt-dlp`/`ffmpeg` are already installed at first launch, the alert doesn't appear — there's nothing to flag.

## App language

The interface is now fully localized: Polish and English, chosen automatically based on the system language (System Settings → General → Language & Region) — no switch inside the app itself, since macOS already does this for any properly localized app. If the system is set to a language other than these two, Tubio shows Polish (the source language of the text in the code).

Technically: every string in the interface is a key in `Sources/Resources/Localizable.xcstrings` (a String Catalog, native to Xcode 15+) — the keys are the Polish text from the code itself, and the file adds English translations for them. Adding another language means adding a third list of translations to this one file, with no Swift changes. A handful of things were deliberately left untranslated, because they're identical in both languages or aren't words at all: the app name, tool names (`yt-dlp`, `ffmpeg`, `brew`), resolution labels (`1080p` etc.), and the filename template syntax (`%(title)s.%(ext)s`).

## Requirements

- macOS 14+
- [Homebrew](https://brew.sh)
- `yt-dlp` and `ffmpeg`: `brew install yt-dlp ffmpeg`
- Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen) to build the project from `project.yml` (`brew install xcodegen`)

### Uninstalling yt-dlp / ffmpeg

```bash
brew uninstall yt-dlp ffmpeg
```

Useful e.g. for a clean reinstall, if you suspect a broken/outdated install. After uninstalling, Tubio will show the "yt-dlp and/or ffmpeg missing" screen with a ready-to-copy install command.

## Building

```bash
cd Tubio
xcodegen generate
open Tubio.xcodeproj
```

## Architecture (brief)

- `Services/BinaryLocator.swift` — locating `yt-dlp`/`ffmpeg`/`brew` on disk.
- `Services/HomebrewUpdater.swift` — checking for and installing `yt-dlp`/`ffmpeg` updates via `brew outdated`/`brew upgrade` (see "Checking for updates" above).
- `Services/YtdlpArgs.swift` — building argument arrays (never a shell string) for each `yt-dlp` invocation; the format selector, sort fields, and postprocessing flags are a port of the original project's actual logic (see above).
- `Services/YtdlpRunner.swift` — safely running `Process`, an event stream (`AsyncStream<YtdlpEvent>`) with progress/stderr/final file path/exit code; reads both stdout and stderr the same way the original engine does.
- `Services/ProgressParser.swift` — parsing `RAW|...` lines from `--progress-template` (the same set of fields as the original, with the same fallback chain for computing the percentage).
- `Services/DestinationParser.swift` — determining the final file path from `yt-dlp` lines like "Destination:"/"Merging formats into", with a "confidence" system identical to the original's.
- `Models/` — `MediaInfo`/`YtdlpFormat` (decoding JSON from `yt-dlp -J`), `DownloadItem`/`DownloadProgress`/`DownloadState`.
- `ViewModels/DownloadQueueViewModel.swift` — the queue, concurrent-download limit, settings in `UserDefaults`.
- `Views/` — `ContentView` (main window, light/dark depending on the system, first-launch alert), `DownloadCardView` (a queue row with a bigger thumbnail), `SettingsView`, `MissingToolsView`.
- `Resources/Localizable.xcstrings` — a String Catalog with translations for every interface string (Polish → English); see "App language" above.

## Responsible use

Tubio is a general-purpose video-downloading tool — just like `yt-dlp` itself, or dozens of similar GUIs. It doesn't bypass any DRM protections, doesn't make copyrighted content available to anyone else, doesn't break any technical locks. What you download and what you do with it is governed by the terms of service of the site you're downloading from, and by the copyright law applicable in your jurisdiction — that's your responsibility as the user, same as with any other tool of this kind.
