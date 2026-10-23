import Foundation

/// Decoded from `yt-dlp -J --no-playlist <url>` (a single JSON object
/// describing one video — yt-dlp's `-J`/`--dump-json` flag). Only the
/// fields Tubio actually uses are declared; yt-dlp's real output has
/// dozens more per extractor, and `Decodable` silently ignores keys we
/// don't list, which is exactly the robustness we want here (we must not
/// fail to parse just because some obscure site adds an extra field).
struct MediaInfo: Decodable {
  let id: String
  let title: String
  let thumbnail: String?
  /// Seconds. `nil` for livestreams and a few extractors that don't report it.
  let duration: Double?
  let webpageURL: String?
  let formats: [YtdlpFormat]

  enum CodingKeys: String, CodingKey {
    case id, title, thumbnail, duration, formats
    case webpageURL = "webpage_url"
  }

  /// Distinct video heights (1080, 720, …) actually offered for this
  /// specific video, descending — drives which quality buttons
  /// `DownloadCard` shows, so we never offer "1080p" for a video that only
  /// has up to 480p. Only counts formats with an actual video track
  /// (`vcodec` present and not `"none"` — yt-dlp uses the literal string
  /// `"none"` to mark audio-only or video-only-less formats).
  var availableHeights: [Int] {
    let heights = formats.compactMap { format -> Int? in
      guard let vcodec = format.vcodec?.lowercased(), vcodec != "none", vcodec != "images" else {
        // "none" marks an audio-only format; "images" marks a storyboard
        // (a grid of thumbnail frames some sites expose as a fake "format")
        // — same two exclusions the analyzed original project applies in
        // `is_real_video_codec` before it'll call something a real video
        // stream.
        return nil
      }
      return format.height
    }
    return Array(Set(heights)).sorted(by: >)
  }

  /// Whether this video has any audio track at all worth offering as an
  /// "audio only" download — true for almost everything, false for a
  /// handful of silent/video-only sources.
  var hasAudio: Bool {
    formats.contains { format in
      guard let acodec = format.acodec else { return false }
      return acodec != "none"
    }
  }
}

/// One entry from yt-dlp's `formats` array. yt-dlp already does the hard
/// work of normalizing wildly different per-site metadata into this shape —
/// Tubio doesn't attempt to replicate that, just reads the result.
struct YtdlpFormat: Decodable {
  let formatId: String?
  let ext: String?
  let vcodec: String?
  let acodec: String?
  let height: Int?
  let filesize: Int64?
  let filesizeApprox: Int64?

  enum CodingKeys: String, CodingKey {
    case formatId = "format_id"
    case ext, vcodec, acodec, height, filesize
    case filesizeApprox = "filesize_approx"
  }
}

/// A playlist/channel URL returns an entries array instead of a single
/// video object. Tubio treats "is this a playlist" as a yes/no question
/// up front (see `DownloadQueueViewModel.fetch`) by trying this shape
/// first, falling back to `MediaInfo` when `entries` is absent.
struct PlaylistInfo: Decodable {
  let id: String
  let title: String?
  let entries: [PlaylistEntry]

  struct PlaylistEntry: Decodable {
    let id: String
    let title: String?
    let url: String?
  }
}

/// The quality a person picked for one download — intentionally a small,
/// fixed set of buckets rather than yt-dlp's raw `format_id` strings (which
/// vary wildly per extractor and are meaningless to look at). Each case
/// maps to a yt-dlp `-f` *selector expression* in
/// `YtdlpArgs.formatArgs(for:)`, letting yt-dlp itself pick the actual
/// best-matching stream(s) — far more robust than Tubio trying to
/// pre-compute an exact `format_id`.
enum QualityOption: Hashable, Identifiable {
  case best
  case height(Int)
  case audioOnly

  var id: String {
    switch self {
    case .best: return "best"
    case .height(let h): return "h\(h)"
    case .audioOnly: return "audio"
    }
  }

  var label: String {
    switch self {
    case .best: return "Najlepsza jakość"
    case .height(let h): return "\(h)p"
    case .audioOnly: return "Tylko audio (MP3)"
    }
  }
}
