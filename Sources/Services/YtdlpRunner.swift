import Darwin
import Foundation

enum YtdlpRunnerError: LocalizedError {
  case processFailedToLaunch(String)
  case nonZeroExit(Int32)
  case emptyOutput
  case decodingFailed(String)

  var errorDescription: String? {
    switch self {
    case .processFailedToLaunch(let reason):
      return "Nie udało się uruchomić yt-dlp: \(reason)"
    case .nonZeroExit(let code):
      return "yt-dlp zakończył pracę z błędem (kod \(code))."
    case .emptyOutput:
      return "yt-dlp nie zwrócił żadnych danych."
    case .decodingFailed(let reason):
      return "Nie udało się odczytać informacji o wideo: \(reason)"
    }
  }
}

enum YtdlpEvent {
  case progress(DownloadProgress)
  case stderrLine(String)
  /// The best (highest-confidence) destination path seen so far, from
  /// `DestinationParser` reading yt-dlp's own ordinary output lines — see
  /// that type's doc comment. Yielded every time a higher-confidence match
  /// arrives, so by the time `.finished(status: 0)` shows up the last one
  /// received is reliably the real final file.
  case finalFilePath(String)
  /// Yielded exactly once, right before the stream ends, carrying the
  /// process's real exit code — `DownloadQueueViewModel` uses this (rather
  /// than, say, "did we ever see a 100% progress line") to decide whether
  /// the download actually succeeded, since a 0 exit status is yt-dlp's own
  /// authoritative "everything — download, merge, postprocessing — worked"
  /// signal.
  case finished(status: Int32)
}

/// Thin, safe wrapper around `Process` for invoking `yt-dlp`. The one rule
/// this type exists to enforce: arguments are always handed to
/// `Process.arguments` as a `[String]` — never interpolated into a single
/// shell command string. That's what makes an arbitrary, fully
/// user-controlled URL (or a pasted bearer token, custom filename, etc.)
/// safe to pass straight through: each array element becomes exactly one
/// argument to the `exec`'d program, with no shell in between to
/// reinterpret `;`, `$()`, quotes, or anything else in it.
@MainActor
final class YtdlpRunner {
  private let ytdlp: URL
  private let binDirectory: String

  init(located: BinaryLocator.Located) {
    self.ytdlp = located.ytdlp
    self.binDirectory = BinaryLocator.binDirectory(for: located)
  }

  /// Fetches metadata for a single URL (`yt-dlp -J`) and decodes it. Runs
  /// to completion and returns the whole JSON at once — info fetches are
  /// quick (a single HTTP round trip from yt-dlp's side in the common
  /// case), so there's no need for the incremental/streaming machinery
  /// `runDownload` below uses.
  func fetchInfo(url: String) async throws -> MediaInfo {
    let output = try await run(arguments: YtdlpArgs.infoArgs(url: url))
    guard let data = output.stdout.data(using: .utf8), !data.isEmpty else {
      throw YtdlpRunnerError.emptyOutput
    }
    let decoder = JSONDecoder()
    do {
      return try decoder.decode(MediaInfo.self, from: data)
    } catch {
      throw YtdlpRunnerError.decodingFailed(error.localizedDescription)
    }
  }

  /// Starts a download and returns a live event stream (progress ticks +
  /// raw stderr lines, for surfacing yt-dlp's own error text verbatim when
  /// something goes wrong) plus a handle to cancel it. The stream finishes
  /// normally when the process exits; the caller (`DownloadQueueViewModel`)
  /// is the one that decides what a given exit code means for the item's
  /// visible state.
  func startDownload(
    url: String,
    quality: QualityOption,
    outputTemplate: String,
    embedThumbnail: Bool,
    embedSubtitlesIfAvailable: Bool
  ) -> (events: AsyncStream<YtdlpEvent>, handle: RunningProcess) {
    let args = YtdlpArgs.downloadArgs(
      url: url,
      quality: quality,
      outputTemplate: outputTemplate,
      embedThumbnail: embedThumbnail,
      embedSubtitlesIfAvailable: embedSubtitlesIfAvailable
    )

    let process = makeProcess(arguments: args)
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let handle = RunningProcess(process: process)

    let stream = AsyncStream<YtdlpEvent> { continuation in
      // The original project parses *both* stdout and stderr for progress
      // and destination lines (yt-dlp's own split between the two streams
      // isn't fully consistent across versions/platforms), so both buffers
      // below run the exact same two checks. Only stderr lines are also
      // forwarded raw via `.stderrLine`, to show verbatim in the UI if the
      // download ends up failing.
      var bestDestinationConfidence = -1

      func handleLine(_ line: String) {
        if let progress = ProgressParser.parse(line: line) {
          continuation.yield(.progress(progress))
          return
        }
        if let match = DestinationParser.parse(line: line), match.confidence >= bestDestinationConfidence {
          bestDestinationConfidence = match.confidence
          continuation.yield(.finalFilePath(match.path))
        }
      }

      let stdoutBuffer = LineBuffer { line in
        handleLine(line)
      }
      let stderrBuffer = LineBuffer { line in
        handleLine(line)
        continuation.yield(.stderrLine(line))
      }

      stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
        let data = fh.availableData
        if data.isEmpty {
          fh.readabilityHandler = nil
          stdoutBuffer.flush()
        } else {
          stdoutBuffer.feed(data)
        }
      }
      stderrPipe.fileHandleForReading.readabilityHandler = { fh in
        let data = fh.availableData
        if data.isEmpty {
          fh.readabilityHandler = nil
          stderrBuffer.flush()
        } else {
          stderrBuffer.feed(data)
        }
      }

      process.terminationHandler = { finished in
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutBuffer.flush()
        stderrBuffer.flush()
        continuation.yield(.finished(status: finished.terminationStatus))
        continuation.finish()
      }

      do {
        try process.run()
      } catch {
        continuation.finish()
      }
    }

    return (stream, handle)
  }

  // MARK: - Internals

  private struct ProcessOutput {
    let status: Int32
    let stdout: String
    let stderr: String
  }

  /// This was the actual cause of a download's card getting stuck forever
  /// on "Wczytywanie informacji…" — a classic `Process`/`Pipe` deadlock,
  /// not anything wrong with yt-dlp, the network, or the harmless macOS
  /// system-log noise (`com.apple.linkd.autoShortcut`, `ViewBridge
  /// Terminated`, …) that shows up for practically any unsigned app and
  /// isn't related to this at all.
  ///
  /// The old version of this method only ever read `stdoutPipe`/`stderrPipe`
  /// *after* `process.terminationHandler` fired — i.e. after the process
  /// had already exited. But a macOS pipe's kernel buffer is small (on the
  /// order of 64 KB), and `yt-dlp -J`'s JSON dump for one real video —
  /// full `formats` array, thumbnails list, description, chapters, … — is
  /// routinely several hundred KB. Once yt-dlp fills that buffer it blocks
  /// inside its own `write()` call waiting for a reader; since nothing was
  /// reading the pipe *while the process was still running*, it could
  /// never finish writing, so it could never exit, so `terminationHandler`
  /// could never fire — `fetchInfo` hung forever waiting for a process
  /// that was itself waiting for `fetchInfo`. `startDownload` below never
  /// had this bug (it already drains both pipes incrementally via
  /// `readabilityHandler` as data arrives); this fixes `run()` the same way.
  private func run(arguments: [String]) async throws -> ProcessOutput {
    try await withCheckedThrowingContinuation { continuation in
      let process = makeProcess(arguments: arguments)
      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe

      let stdoutAccumulator = DataAccumulator()
      let stderrAccumulator = DataAccumulator()

      stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
        let chunk = fh.availableData
        if chunk.isEmpty {
          fh.readabilityHandler = nil
        } else {
          stdoutAccumulator.append(chunk)
        }
      }
      stderrPipe.fileHandleForReading.readabilityHandler = { fh in
        let chunk = fh.availableData
        if chunk.isEmpty {
          fh.readabilityHandler = nil
        } else {
          stderrAccumulator.append(chunk)
        }
      }

      process.terminationHandler = { finished in
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        // Belt-and-suspenders against a narrow ordering race:
        // `terminationHandler` and the last `readabilityHandler` call can
        // in principle fire on different queues in either order, so grab
        // anything still sitting in the pipe (non-blocking at this point —
        // the writer has already exited, so this is immediately at EOF)
        // rather than trusting the handler to have already delivered every
        // last byte.
        if let trailing = try? stdoutPipe.fileHandleForReading.readToEnd(), !trailing.isEmpty {
          stdoutAccumulator.append(trailing)
        }
        if let trailing = try? stderrPipe.fileHandleForReading.readToEnd(), !trailing.isEmpty {
          stderrAccumulator.append(trailing)
        }
        let output = ProcessOutput(
          status: finished.terminationStatus,
          stdout: String(data: stdoutAccumulator.snapshot(), encoding: .utf8) ?? "",
          stderr: String(data: stderrAccumulator.snapshot(), encoding: .utf8) ?? ""
        )
        if finished.terminationStatus == 0 {
          continuation.resume(returning: output)
        } else {
          continuation.resume(throwing: YtdlpRunnerError.nonZeroExit(finished.terminationStatus))
        }
      }

      do {
        try process.run()
      } catch {
        continuation.resume(throwing: YtdlpRunnerError.processFailedToLaunch(error.localizedDescription))
      }
    }
  }

  private func makeProcess(arguments: [String]) -> Process {
    let process = Process()
    process.executableURL = ytdlp
    process.arguments = arguments

    // So yt-dlp's own internal `ffmpeg` lookup (it shells out to a bare
    // `ffmpeg` by name for merging/remuxing/extracting audio) finds the
    // exact copy `BinaryLocator` found, rather than whatever a bare PATH
    // lookup from this GUI app's own (likely minimal) environment would
    // turn up.
    var env = ProcessInfo.processInfo.environment
    let existingPath = env["PATH"] ?? "/usr/bin:/bin"
    env["PATH"] = "\(binDirectory):\(existingPath)"
    process.environment = env

    return process
  }
}

/// A cancellation handle for a download started with `startDownload`.
/// Deliberately a plain `SIGTERM` to the `yt-dlp` process itself rather
/// than a process-group kill: yt-dlp has its own signal handling and
/// generally cleans up an in-flight `ffmpeg` child when it receives one.
/// A more surgical process-group-wide kill (which the upstream project
/// this app was inspired by does implement, with platform-specific code
/// for both Unix process groups and Windows Job Objects) is a reasonable
/// future improvement if orphaned `ffmpeg` processes turn out to be a
/// problem in practice — left out here rather than shipped untested.
final class RunningProcess {
  private let process: Process
  private(set) var isPaused = false

  init(process: Process) {
    self.process = process
  }

  func cancel() {
    guard process.isRunning else { return }
    if isPaused {
      // A `SIGTERM` delivered to a `SIGSTOP`-stopped process is held
      // pending rather than acted on until the process is continued, so a
      // cancel sent while paused would otherwise silently do nothing until
      // someone happened to resume it. Resuming right before terminating
      // avoids that — the process gets to actually see, and act on, the
      // signal we're about to send it.
      kill(process.processIdentifier, SIGCONT)
      isPaused = false
    }
    process.terminate()
  }

  /// Not something the analyzed original project has at all — it only
  /// ever starts or cancels a download, no pause/resume of any kind (this
  /// was checked directly against its source rather than assumed). This is
  /// Tubio's own addition, built the plain Unix way: `SIGSTOP` freezes
  /// the process in place (no more CPU time, no more reads/writes on its
  /// open socket) until `resume()` sends `SIGCONT` — the same two signals
  /// a shell's job control uses for Ctrl-Z / `fg`. It only suspends the
  /// `yt-dlp` process itself, not a separately-spawned `ffmpeg` child
  /// already merging/remuxing by the time this is called — pausing during
  /// the actual download (the overwhelming majority of a transfer's time)
  /// works cleanly; pausing mid-merge just won't do much until that step
  /// finishes on its own. If the paused connection times out on the
  /// server's end before `resume()`, yt-dlp's own `--continue` (on by
  /// default) picks the partial file back up rather than restarting, so a
  /// long pause costs a reconnect, not lost progress.
  func pause() {
    guard process.isRunning, !isPaused else { return }
    kill(process.processIdentifier, SIGSTOP)
    isPaused = true
  }

  func resume() {
    guard process.isRunning, isPaused else { return }
    kill(process.processIdentifier, SIGCONT)
    isPaused = false
  }
}

/// Accumulates raw bytes from a pipe's `readabilityHandler` as they arrive,
/// for callers (like `YtdlpRunner.run`) that need the *whole* output at the
/// end rather than line-by-line — see `run`'s doc comment for why reading a
/// pipe only after the process exits can deadlock. `append`/`snapshot` are
/// called from different queues (the `FileHandle`'s own monitoring queue vs.
/// `Process.terminationHandler`'s queue), hence the lock — cheap, and never
/// actually contended in practice, but a data race here would be a classic
/// "works in testing, hangs or corrupts output occasionally in the field"
/// bug not worth risking.
private final class DataAccumulator {
  private var data = Data()
  private let lock = NSLock()

  func append(_ chunk: Data) {
    lock.lock()
    data.append(chunk)
    lock.unlock()
  }

  func snapshot() -> Data {
    lock.lock()
    defer { lock.unlock() }
    return data
  }
}

/// Accumulates raw bytes from a pipe's `readabilityHandler` into complete
/// `\n`-terminated lines, since `Pipe`/`FileHandle` hands over whatever
/// chunk of bytes happened to be available — not necessarily aligned to a
/// line boundary — on every call.
private final class LineBuffer {
  private var pending = Data()
  private let onLine: (String) -> Void

  init(onLine: @escaping (String) -> Void) {
    self.onLine = onLine
  }

  func feed(_ data: Data) {
    pending.append(data)
    while let newlineIndex = pending.firstIndex(of: 0x0A) {
      let lineData = pending[..<newlineIndex]
      pending.removeSubrange(...newlineIndex)
      if let line = String(data: lineData, encoding: .utf8) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          onLine(trimmed)
        }
      }
    }
  }

  func flush() {
    if let line = String(data: pending, encoding: .utf8) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        onLine(trimmed)
      }
    }
    pending.removeAll()
  }
}
