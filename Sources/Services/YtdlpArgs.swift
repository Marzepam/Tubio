import Foundation

/// Builds `yt-dlp` argument *arrays* (never a shell string — see
/// `YtdlpRunner`, which passes these straight to `Process.arguments`).
///
/// Unlike the first draft of this file, the format-selector, sort-field,
/// progress-template and postprocessing flags below are a direct, faithful
/// port of the actual invocation logic in the analyzed Open Video
/// Downloader project (`src-tauri/src/runners/ytdlp_args/format_args.rs`,
/// `output_args.rs`, and `ytdlp_runner.rs`'s `with_progress_args`) — not a
/// reinvention. Tubio is for personal use, not for sale or
/// redistribution, so there's no AGPL-redistribution concern in matching
/// its proven argument shapes line-for-line rather than inventing a
/// different (and, it turned out, less reliable) one. The one simplification
/// kept is dropping that project's per-track language-preference branches
/// (`lang:xx` selectors) — Tubio's UI has no language picker — which
/// collapses cleanly to its own "no language preference" fallback path, so
/// the actual selector strings produced are identical to what that project
/// emits for a listener who also hasn't set a language preference.
enum YtdlpArgs {
  /// yt-dlp's own documented feature for a stable, machine-readable
  /// progress line instead of the human-oriented terminal progress bar.
  /// The exact field list and the `RAW|` tag match the original project's
  /// template byte-for-byte — see `ProgressParser`, which parses this same
  /// 9-field shape.
  static let progressTemplate =
    "RAW|%(progress.percent|)s|%(progress._percent_str|)s|%(progress.speed|)s|%(progress.eta|)s|%(progress.downloaded_bytes|)s|%(progress.total_bytes|)s|%(progress.total_bytes_estimate|)s|%(progress.fragment_index|)s|%(progress.fragment_count|)s"

  static var progressArgs: [String] {
    [
      "--newline",
      "--progress",
      "--no-color",
      "--progress-template", progressTemplate,
      "--progress-delta", "0.5",
    ]
  }

  /// Base args every invocation gets, mirroring `YtdlpRunner::new()` in the
  /// original project (which seeds `--encoding utf-8` before anything else).
  static var baseArgs: [String] { ["--encoding", "utf-8"] }

  /// `-J` dumps the info JSON to stdout instead of downloading.
  /// `--flat-playlist` is in the original's info-fetch call too — it only
  /// changes behavior for an actual playlist URL (resolved per-entry
  /// instead of eagerly), and is a no-op for a single video, so keeping it
  /// costs nothing and matches the original exactly.
  static func infoArgs(url: String) -> [String] {
    baseArgs + formatArgs(for: .best) + ["--no-playlist", "-J", "--flat-playlist", url]
  }

  // MARK: - Format selection (`-f` / `-S`)

  /// `-f <selector> -S <sort>` for the given quality — ported from
  /// `format_args.rs`'s `build_format_args`/`build_video_format_args`/
  /// `build_audio_format_args`, with the language-preference branches
  /// dropped (see the type's doc comment).
  static func formatArgs(for quality: QualityOption) -> [String] {
    switch quality {
    case .audioOnly:
      return ["-x", "-f", "ba/best", "-S", "lang,aext:mp3"]
    case .best:
      return ["-f", combinedSelector(maxHeight: nil), "-S", videoSort(maxHeight: nil)]
    case .height(let maxHeight):
      return ["-f", combinedSelector(maxHeight: maxHeight), "-S", videoSort(maxHeight: maxHeight)]
    }
  }

  /// Port of `combined_selector`'s no-language-preference fallback branch —
  /// the only branch reachable now that Tubio never sets a language
  /// preference. With no fps constraint (Tubio doesn't expose one
  /// either), `apply_height_and_fps`/`apply_height` collapse to the same
  /// string and `apply_fps`/`apply` collapse to the bare selector, so the
  /// four-tier fallback de-duplicates to exactly two tiers: height-bounded,
  /// then unbounded.
  private static func combinedSelector(maxHeight: Int?) -> String {
    guard let maxHeight else {
      return "bestvideo*+bestaudio/best"
    }
    return "bestvideo*[height<=\(maxHeight)]+bestaudio/best[height<=\(maxHeight)]/bestvideo*+bestaudio/best"
  }

  /// Port of `video_sort_fields`: `lang` as a bare preference marker (no
  /// language chosen), the requested height as a *sort* preference (on top
  /// of the selector's hard `[height<=N]` cap above — this is what makes
  /// yt-dlp prefer e.g. 1080p over 480p among the formats the selector lets
  /// through, rather than an arbitrary one of them), then the same
  /// mp4-container preferences the original applies by default
  /// (`VideoContainer::Mp4` is that project's default, and Tubio always
  /// remuxes to mp4 too — see `postprocessArgs`).
  private static func videoSort(maxHeight: Int?) -> String {
    var fields = ["lang"]
    if let maxHeight {
      fields.append("height:\(maxHeight)")
    }
    fields.append(contentsOf: ["vcodec:avc1", "acodec:aac", "vext:mp4", "vext:m4a"])
    return fields.joined(separator: ",")
  }

  // MARK: - Postprocessing / output args

  /// Ported from `output_args.rs`'s `build_output_args`, fixed to that
  /// project's own *default* settings profile (`TranscodePolicy::AllowReencode`,
  /// `VideoContainer::Mp4`, `AudioFormat::Mp3`, no custom postprocess
  /// preset) — Tubio doesn't expose those as separate settings, so it
  /// always builds the args for the configuration most people actually run
  /// that project with out of the box:
  /// - video: `--merge-output-format mp4 --remux-video mp4` (a *remux*, not
  ///   a re-encode — this just repackages whatever streams yt-dlp picked
  ///   into an mp4 container, it doesn't transcode video/audio, so it's
  ///   fast and lossless)
  /// - audio: `--audio-format mp3 --audio-quality 0` (0 = yt-dlp's own
  ///   "best" VBR quality)
  /// - `--add-metadata` always on, matching the original's default
  /// - `--embed-thumbnail` / subtitle flags only when the matching toggle
  ///   in Settings is on
  /// - no `--restrict-filenames` — the original defaults that *off*, so
  ///   Tubio's earlier draft (which always forced it on) was actually
  ///   diverging from the real engine here too.
  static func postprocessArgs(
    quality: QualityOption,
    embedThumbnail: Bool,
    embedSubtitlesIfAvailable: Bool
  ) -> [String] {
    var args = ["--output-na-placeholder", ""]

    switch quality {
    case .audioOnly:
      args.append(contentsOf: ["--audio-format", "mp3", "--audio-quality", "0"])
      if embedThumbnail {
        args.append("--embed-thumbnail")
      }
    case .best, .height:
      args.append(contentsOf: ["--merge-output-format", "mp4", "--remux-video", "mp4"])
      if embedThumbnail {
        args.append("--embed-thumbnail")
      }
    }

    args.append("--add-metadata")

    if embedSubtitlesIfAvailable {
      args.append(contentsOf: ["--write-subs", "--write-auto-subs", "--embed-subs", "--sub-langs", "all"])
    }

    return args
  }

  // MARK: - Full download invocation

  /// Full argument list for an actual download. `outputTemplate` is a
  /// yt-dlp output-template string, built by the caller from the person's
  /// chosen destination folder plus `DownloadQueueViewModel.filenameTemplate`.
  ///
  /// Note what's deliberately *not* here any more: a `--print after_move:…`
  /// flag. The original project doesn't use one — it determines the final
  /// file path by watching yt-dlp's own ordinary progress/postprocessing
  /// output lines (`[download] Destination: …`, `[Merger] Merging formats
  /// into "…"`, `[VideoRemuxer] Destination: …`, …) and picking the
  /// highest-confidence one it's seen, exactly like `DestinationParser`
  /// here now does. `--print after_move` is a legitimate yt-dlp feature,
  /// but it's not what the original engine relies on, and using a different
  /// mechanism than the proven one is exactly what this rewrite is fixing.
  static func downloadArgs(
    url: String,
    quality: QualityOption,
    outputTemplate: String,
    embedThumbnail: Bool,
    embedSubtitlesIfAvailable: Bool
  ) -> [String] {
    var args = baseArgs
    args.append(contentsOf: progressArgs)
    args.append(contentsOf: formatArgs(for: quality))
    args.append(contentsOf: ["--no-playlist"])
    args.append(contentsOf: postprocessArgs(
      quality: quality,
      embedThumbnail: embedThumbnail,
      embedSubtitlesIfAvailable: embedSubtitlesIfAvailable
    ))
    args.append(contentsOf: ["-o", outputTemplate])
    args.append(url)
    return args
  }
}
