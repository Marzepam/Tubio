import Foundation

/// One line item in the queue: a URL someone pasted in, from "just added"
/// all the way through to a finished (or failed) file. A `class` rather
/// than a `struct` because it's held and mutated in place from an async
/// progress stream (`YtdlpRunner`) while SwiftUI observes it — `struct`
/// copies would silently detach the view from the version being updated.
@MainActor
final class DownloadItem: ObservableObject, Identifiable {
  let id = UUID()
  let originalURLString: String

  @Published var state: DownloadState = .fetchingInfo
  @Published var mediaInfo: MediaInfo?
  @Published var selectedQuality: QualityOption = .best
  @Published var progress = DownloadProgress()
  /// The actual, final file on disk — tracked from yt-dlp's own ordinary
  /// output lines as the download/merge/postprocess steps go by (see
  /// `DestinationParser` and `YtdlpEvent.finalFilePath`), the same way the
  /// analyzed original project determines it. Set once a download finishes
  /// successfully; "Pokaż w Finderze" / "Otwórz" act on it directly.
  @Published var completedFileURL: URL?
  @Published var errorMessage: String?
  /// Set the moment the person presses "Pobierz teraz" (or "Spróbuj
  /// ponownie") — `false` for an item that's merely sitting in `.queued`
  /// after its info finished fetching, still waiting to be reviewed.
  /// `DownloadQueueViewModel.startNextIfPossible()` only auto-starts items
  /// where this is `true`, which is what stops a freshly-added link from
  /// starting to download before there's been any chance to pick a
  /// resolution.
  var userRequestedDownload = false

  init(urlString: String) {
    self.originalURLString = urlString
  }

  var displayTitle: String {
    mediaInfo?.title ?? originalURLString
  }
}

enum DownloadState: Equatable {
  /// Just added — running `yt-dlp -J` to fetch title/thumbnail/available
  /// qualities before anything is downloaded.
  case fetchingInfo
  /// Info fetched, waiting for the person to confirm quality & press
  /// download (or waiting its turn in the concurrency-limited queue — see
  /// `DownloadQueueViewModel.maxConcurrentDownloads`).
  case queued
  case downloading
  /// A real `SIGSTOP` pause of the `yt-dlp` process, not a cancel — see
  /// `DownloadQueueViewModel.pause(_:)` / `RunningProcess.pause()`.
  case paused
  case completed
  case failed
  case cancelled
}

/// Parsed from yt-dlp's own progress-template output (see
/// `YtdlpArgs.progressArgs` / `ProgressParser`) — mirrors the
/// `RAW|percent|...` line format the upstream project uses for the same
/// reason: yt-dlp's default human-readable progress bar is meant for a
/// terminal, not for a GUI to parse reliably, so both projects ask yt-dlp
/// for an explicit, machine-readable template instead.
struct DownloadProgress: Equatable {
  var percent: Double = 0
  var downloadedBytes: Int64?
  var totalBytes: Int64?
  var speedBytesPerSecond: Double?
  var etaSeconds: Int?
}
