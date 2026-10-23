import Combine
import Foundation
import AppKit

/// Owns the whole queue: locating `yt-dlp`/`ffmpeg`, fetching metadata for
/// newly-added URLs, running downloads up to a concurrency limit, and the
/// handful of persisted settings (destination folder, filename template,
/// default quality). One instance lives for the app's lifetime as a
/// `@StateObject` in `ContentView` — mirrors the shape of `EditorViewModel`
/// in Movi, just for a queue of items instead of a single open video.
@MainActor
final class DownloadQueueViewModel: ObservableObject {
  @Published private(set) var items: [DownloadItem] = []
  @Published private(set) var tools: BinaryLocator.Located?
  @Published var globalErrorMessage: String?
  /// Set to `true` exactly once, the very first time Tubio is ever
  /// launched on a machine, if `yt-dlp`/`ffmpeg` aren't found at that
  /// moment — `ContentView` binds an `.alert` to this to greet a brand-new
  /// install with a heads-up, on top of (not instead of) the persistent
  /// `MissingToolsView` screen that already explains the same thing (with
  /// a copy-pasteable `brew install` command) for as long as the tools
  /// stay missing. Never fires again after the first launch, by design —
  /// see `Keys.hasRunBefore` below.
  @Published var showFirstLaunchToolsAlert = false

  // MARK: Settings (persisted to UserDefaults — this app has no need for a
  // richer settings store than that; there's nothing here sensitive enough
  // to warrant the kind of encrypted-vault treatment Movi/the upstream
  // project give actual site credentials, because Tubio doesn't handle
  // credentials at all — see README's "What this app deliberately leaves
  // out" section).

  @Published var destinationDirectory: URL {
    didSet { UserDefaults.standard.set(destinationDirectory.path, forKey: Keys.destinationDir) }
  }
  @Published var filenameTemplate: String {
    didSet { UserDefaults.standard.set(filenameTemplate, forKey: Keys.filenameTemplate) }
  }
  @Published var defaultQuality: QualityOption {
    didSet { UserDefaults.standard.set(defaultQuality.id, forKey: Keys.defaultQuality) }
  }
  @Published var embedThumbnail: Bool {
    didSet { UserDefaults.standard.set(embedThumbnail, forKey: Keys.embedThumbnail) }
  }
  @Published var embedSubtitles: Bool {
    didSet { UserDefaults.standard.set(embedSubtitles, forKey: Keys.embedSubtitles) }
  }
  @Published var maxConcurrentDownloads: Int {
    didSet { UserDefaults.standard.set(maxConcurrentDownloads, forKey: Keys.maxConcurrent) }
  }

  private enum Keys {
    static let destinationDir = "destinationDirectory"
    static let filenameTemplate = "filenameTemplate"
    static let defaultQuality = "defaultQuality"
    static let embedThumbnail = "embedThumbnail"
    static let embedSubtitles = "embedSubtitles"
    static let maxConcurrent = "maxConcurrentDownloads"
    static let hasRunBefore = "hasRunBefore"
  }

  private var runner: YtdlpRunner?
  private var runningHandles: [UUID: RunningProcess] = [:]

  /// `DownloadItem` is its own `ObservableObject`, so a `DownloadCardView`
  /// that holds one directly (`@ObservedObject var item`) redraws correctly
  /// when e.g. `item.state` changes. But *this* view model only publishes
  /// changes to the `items` array itself (an insert/remove) — reassigning
  /// one element's own `@Published` property doesn't touch the array, so it
  /// never reaches `objectWillChange` here, and anything that reads
  /// `items` directly from a view that only observes the view model (not
  /// each item) — like `ContentView`'s "Wyczyść ukończone" enabled state —
  /// was going stale until some unrelated array mutation (e.g. removing a
  /// different item) forced a redraw. Forwarding each item's own
  /// `objectWillChange` into this view model's is what fixes that: now
  /// *any* change to *any* item republishes here too.
  private var itemSubscriptions: [UUID: AnyCancellable] = [:]

  init() {
    let defaults = UserDefaults.standard
    if let savedPath = defaults.string(forKey: Keys.destinationDir) {
      destinationDirectory = URL(fileURLWithPath: savedPath)
    } else {
      destinationDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser
    }
    filenameTemplate = defaults.string(forKey: Keys.filenameTemplate) ?? "%(title)s.%(ext)s"
    embedThumbnail = defaults.object(forKey: Keys.embedThumbnail) as? Bool ?? true
    embedSubtitles = defaults.object(forKey: Keys.embedSubtitles) as? Bool ?? false
    let savedConcurrency = defaults.object(forKey: Keys.maxConcurrent) as? Int
    maxConcurrentDownloads = savedConcurrency ?? 2

    if let savedQuality = defaults.string(forKey: Keys.defaultQuality) {
      if savedQuality == "audio" {
        defaultQuality = .audioOnly
      } else if savedQuality.hasPrefix("h"), let height = Int(savedQuality.dropFirst()) {
        defaultQuality = .height(height)
      } else {
        defaultQuality = .best
      }
    } else {
      defaultQuality = .best
    }

    recheckTools()

    // First-launch-only nudge: `UserDefaults` has no entry for this key
    // until this exact line has run once, ever, for this app (persists
    // across future launches same as the settings above). Tools missing
    // on that very first run is the one moment this alert exists for —
    // every later launch, a still-missing install is already covered by
    // `MissingToolsView`, so this doesn't repeat itself.
    if !defaults.bool(forKey: Keys.hasRunBefore) {
      defaults.set(true, forKey: Keys.hasRunBefore)
      if tools == nil {
        showFirstLaunchToolsAlert = true
      }
    }
  }

  func recheckTools() {
    tools = BinaryLocator.locate()
    if let tools {
      runner = YtdlpRunner(located: tools)
    } else {
      runner = nil
    }
  }

  // MARK: Adding URLs

  func addURL(_ rawString: String) {
    let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard let url = URL(string: trimmed), let scheme = url.scheme, scheme.hasPrefix("http") else {
      globalErrorMessage = String(
        format: String(localized: "To nie wygląda na prawidłowy adres (http/https): %@", comment: "Error shown when the pasted text isn't a valid http/https URL"),
        trimmed
      )
      return
    }
    guard runner != nil else {
      globalErrorMessage = String(localized: "yt-dlp / ffmpeg nie zostały znalezione — zobacz ekran instalacji narzędzi.", comment: "Error shown when trying to add a URL while yt-dlp/ffmpeg aren't installed")
      return
    }
    // Same link added twice while still in flight is a no-op, not a second
    // queue entry — easy to do by pasting the same link again before the
    // first fetch finishes.
    guard !items.contains(where: { $0.originalURLString == trimmed && $0.state != .failed && $0.state != .cancelled }) else {
      return
    }

    let item = DownloadItem(urlString: trimmed)
    item.selectedQuality = defaultQuality
    items.insert(item, at: 0)
    itemSubscriptions[item.id] = item.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    }
    Task { await fetchInfo(for: item) }
  }

  private func fetchInfo(for item: DownloadItem) async {
    guard let runner else { return }
    do {
      let info = try await runner.fetchInfo(url: item.originalURLString)
      item.mediaInfo = info
      // Clip the default quality down to what this particular video
      // actually offers — asking for 1080p on a video that tops out at
      // 480p would otherwise just silently fall back inside yt-dlp's own
      // selector, which is correct but means the UI would show "1080p"
      // selected while actually downloading 480p. Showing the real ceiling
      // up front avoids that mismatch.
      if case .height(let wanted) = item.selectedQuality {
        let available = info.availableHeights
        if !available.contains(wanted) {
          item.selectedQuality = available.first.map { QualityOption.height($0) } ?? .best
        }
      }
      // Deliberately *not* followed by `startNextIfPossible()` — a freshly
      // fetched item sits in `.queued` with its quality picker visible and
      // waits for the person to actually press "Pobierz teraz" (see
      // `start(_:)`'s `userRequestedDownload` flag below). The previous
      // version called `startNextIfPossible()` right here, which — since
      // nothing else was usually downloading yet — auto-started it
      // essentially the instant info arrived, never giving anyone a chance
      // to look at the quality menu before the download was already running.
      item.state = .queued
    } catch {
      item.state = .failed
      item.errorMessage = error.localizedDescription
    }
  }

  // MARK: Downloading

  private func activeDownloadCount() -> Int {
    items.filter { $0.state == .downloading }.count
  }

  /// Only ever picks up items the person has actually asked to download
  /// (`userRequestedDownload`) — never a freshly-fetched, not-yet-reviewed
  /// `.queued` item. Called when a download slot frees up (finish/cancel)
  /// so a download that had to wait behind the concurrency limit starts as
  /// soon as it can.
  private func startNextIfPossible() {
    guard activeDownloadCount() < maxConcurrentDownloads else { return }
    guard let next = items.first(where: { $0.state == .queued && $0.userRequestedDownload }) else { return }
    start(next)
  }

  func start(_ item: DownloadItem) {
    guard let runner else { return }
    guard item.state == .queued || item.state == .failed else { return }
    item.userRequestedDownload = true
    guard activeDownloadCount() < maxConcurrentDownloads || item.state == .failed else {
      // Re-queue rather than start immediately if we're already at the
      // concurrency limit — e.g. a retry on a failed item while two
      // others are already running. `userRequestedDownload` is already set
      // above, so `startNextIfPossible()` will pick this one up as soon as
      // a slot frees, without needing another manual click.
      item.state = .queued
      return
    }

    item.state = .downloading
    item.errorMessage = nil
    item.progress = DownloadProgress()

    let outputTemplate = destinationDirectory.appendingPathComponent(filenameTemplate).path
    let (stream, handle) = runner.startDownload(
      url: item.originalURLString,
      quality: item.selectedQuality,
      outputTemplate: outputTemplate,
      embedThumbnail: embedThumbnail,
      embedSubtitlesIfAvailable: embedSubtitles
    )
    runningHandles[item.id] = handle

    Task { [weak self, weak item] in
      guard let self, let item else { return }
      var lastStderrLine: String?
      for await event in stream {
        switch event {
        case .progress(let progress):
          item.progress = progress
        case .stderrLine(let line):
          lastStderrLine = line
        case .finalFilePath(let path):
          item.completedFileURL = URL(fileURLWithPath: path)
        case .finished(let status):
          self.runningHandles[item.id] = nil
          if item.state == .cancelled {
            // Already handled by `cancel(_:)` — don't let a late `.finished`
            // (the process exiting *because* of the SIGTERM we just sent
            // it) overwrite that with `.failed`.
            break
          }
          if status == 0 {
            item.state = .completed
            if item.completedFileURL == nil {
              // Shouldn't normally happen (a "Destination:"/"Merging
              // formats into" line from `DestinationParser` should always
              // precede a 0 exit), but falls back to the destination folder
              // rather than leaving "Pokaż w Finderze" with nothing to
              // point at.
              item.completedFileURL = self.destinationDirectory
            }
          } else {
            item.state = .failed
            item.errorMessage = lastStderrLine ?? String(
              format: String(localized: "yt-dlp zakończył pracę z kodem %d.", comment: "Fallback failure message when yt-dlp exits with a nonzero status and printed nothing to stderr"),
              status
            )
          }
          self.startNextIfPossible()
        }
      }
    }
  }

  func cancel(_ item: DownloadItem) {
    if let handle = runningHandles[item.id] {
      handle.cancel()
      runningHandles[item.id] = nil
    }
    item.state = .cancelled
    startNextIfPossible()
  }

  /// Real `SIGSTOP` pause, not a cancel-and-remember — see
  /// `RunningProcess.pause()`. The paused item no longer counts toward
  /// `activeDownloadCount()` (its state is `.paused`, not `.downloading`),
  /// so a free concurrency slot can let another queued download start
  /// while this one sits frozen; `resume()` below doesn't re-check the
  /// limit before continuing it, on the theory that an explicit "resume
  /// this one" click should just work rather than silently re-queuing.
  func pause(_ item: DownloadItem) {
    guard item.state == .downloading, let handle = runningHandles[item.id] else { return }
    handle.pause()
    item.state = .paused
  }

  func resume(_ item: DownloadItem) {
    guard item.state == .paused, let handle = runningHandles[item.id] else { return }
    handle.resume()
    item.state = .downloading
  }

  func retry(_ item: DownloadItem) {
    guard item.state == .failed else { return }
    item.userRequestedDownload = true
    item.state = .queued
    startNextIfPossible()
  }

  func remove(_ item: DownloadItem) {
    if item.state == .downloading {
      cancel(item)
    }
    items.removeAll { $0.id == item.id }
    itemSubscriptions[item.id] = nil
  }

  func clearCompleted() {
    for item in items where item.state == .completed {
      itemSubscriptions[item.id] = nil
    }
    items.removeAll { $0.state == .completed }
  }

  func revealInFinder(_ item: DownloadItem) {
    guard let file = item.completedFileURL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([file])
  }

  func openFile(_ item: DownloadItem) {
    guard let file = item.completedFileURL else { return }
    NSWorkspace.shared.open(file)
  }
}
