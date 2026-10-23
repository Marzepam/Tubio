import Foundation

/// Finds `yt-dlp` and `ffmpeg` on the person's own machine — Tubio
/// deliberately does **not** bundle, download, or auto-update these itself
/// (unlike the upstream project this app was inspired by, which ships a
/// whole Ed25519-signed binary-update pipeline for exactly this). Shipping
/// and silently updating third-party executables is a real supply-chain
/// responsibility (verifying signatures, hosting mirrors, handling partial
/// downloads, staying current as yt-dlp patches around site changes), and
/// taking that on is a deliberate choice this project is leaving to the
/// person's own package manager instead — see `MissingToolsView` for the
/// "please install via Homebrew" flow this drives when a tool isn't found.
///
/// Both tools are expected to be installed the normal Homebrew way
/// (`brew install yt-dlp ffmpeg`), which lands them in `/opt/homebrew/bin`
/// (Apple Silicon) or `/usr/local/bin` (Intel) — neither of which is
/// reliably on `PATH` for a GUI app launched from Finder/Dock rather than a
/// Terminal shell (GUI apps on macOS don't inherit the user's shell rc
/// files), so this checks those well-known locations explicitly rather than
/// relying on `Process` to resolve a bare command name.
enum BinaryLocator {
  struct Located {
    let ytdlp: URL
    let ffmpeg: URL
  }

  /// Common install locations, in priority order. Homebrew's own prefix
  /// first (covers the vast majority of Mac installs), then a few other
  /// well-known spots (MacPorts, a manually-placed binary, pyenv/pipx
  /// installs of yt-dlp specifically).
  private static let searchDirectories: [String] = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/opt/local/bin",
    "\(NSHomeDirectory())/.local/bin",
  ]

  private static func find(_ name: String) -> URL? {
    let fm = FileManager.default

    for dir in searchDirectories {
      let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
      if fm.isExecutableFile(atPath: candidate.path) {
        return candidate
      }
    }

    // Fall back to whatever `PATH` the app process actually has — covers
    // the case where the person launched Tubio from a Terminal (`open
    // Tubio.app` from a shell that does have yt-dlp on PATH) or has it
    // somewhere unusual we didn't think to check above.
    if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
      for dir in pathEnv.split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
        if fm.isExecutableFile(atPath: candidate.path) {
          return candidate
        }
      }
    }

    return nil
  }

  /// Finds the `brew` executable itself, the same way as `yt-dlp`/`ffmpeg`
  /// above (it lives right next to them, in the same Homebrew prefix) —
  /// used by `HomebrewUpdater` to check for and install yt-dlp/ffmpeg
  /// updates through Homebrew, rather than through a binary-fetching
  /// pipeline of Tubio's own (see that type's doc comment for why).
  static func locateBrew() -> URL? {
    find("brew")
  }

  /// Checks for both tools. `ffmpeg` is required for anything beyond the
  /// simplest "download exactly what the site serves, no merging" case —
  /// merging separate video/audio streams, re-encoding, extracting audio,
  /// and embedding thumbnails/subtitles all go through it — so Tubio
  /// treats it as a hard requirement, same as the upstream project does.
  static func locate() -> Located? {
    guard let ytdlp = find("yt-dlp"), let ffmpeg = find("ffmpeg") else {
      return nil
    }
    return Located(ytdlp: ytdlp, ffmpeg: ffmpeg)
  }

  /// Directory to prepend to `PATH` when running `yt-dlp` as a child
  /// process, so yt-dlp's own internal `ffmpeg` lookup (it shells out to it
  /// by bare name) finds the same copy we located above instead of
  /// potentially finding none / a different one.
  static func binDirectory(for located: Located) -> String {
    located.ffmpeg.deletingLastPathComponent().path
  }
}
