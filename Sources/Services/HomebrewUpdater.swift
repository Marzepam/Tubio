import Foundation

/// Checking for, and installing, `yt-dlp`/`ffmpeg` updates — the
/// Homebrew-native equivalent of the analyzed original project's own
/// binary-update system.
///
/// The original ships a whole Ed25519-signed-manifest, SHA-256-verified
/// downloader for yt-dlp/ffmpeg (`binaries_manager.rs`) — because it
/// manages its own private copies of those binaries, fetched from its own
/// servers. Tubio deliberately doesn't do that (see `BinaryLocator`'s
/// doc comment for the full reasoning): it runs whatever copies Homebrew
/// already manages for the whole system. There's nothing for a port of
/// that manifest-downloader to even point at here — Tubio has no
/// binary-hosting server of its own — so "checking and updating" means
/// asking Homebrew the same way you'd do it yourself from Terminal:
/// `brew outdated yt-dlp ffmpeg` to check, `brew upgrade yt-dlp ffmpeg` to
/// install. That's what this type does, surfaced as a small section in
/// Settings rather than left as a thing you'd only think to do manually.
@MainActor
final class HomebrewUpdater: ObservableObject {
  struct Versions {
    var ytdlp: String?
    var ffmpeg: String?
  }

  enum Status {
    case unknown
    case checking
    case upToDate(Versions)
    case updatesAvailable(outdated: [String], current: Versions)
    case brewNotFound
    case error(String)
  }

  @Published private(set) var status: Status = .unknown
  @Published private(set) var isUpdating = false

  func checkForUpdates(binaryLocated: BinaryLocator.Located?) async {
    status = .checking
    guard let brew = BinaryLocator.locateBrew() else {
      status = .brewNotFound
      return
    }

    let versions = await currentVersions(binaryLocated: binaryLocated)
    do {
      let output = try await Self.run(brew, ["outdated", "--quiet", "yt-dlp", "ffmpeg"])
      let outdated = output.stdout
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
      status = outdated.isEmpty ? .upToDate(versions) : .updatesAvailable(outdated: outdated, current: versions)
    } catch {
      status = .error(error.localizedDescription)
    }
  }

  func upgrade(binaryLocated: BinaryLocator.Located?) async {
    guard let brew = BinaryLocator.locateBrew() else {
      status = .brewNotFound
      return
    }
    isUpdating = true
    _ = try? await Self.run(brew, ["upgrade", "yt-dlp", "ffmpeg"])
    isUpdating = false
    await checkForUpdates(binaryLocated: binaryLocated)
  }

  private func currentVersions(binaryLocated: BinaryLocator.Located?) async -> Versions {
    var versions = Versions()
    if let ytdlp = binaryLocated?.ytdlp,
       let output = try? await Self.run(ytdlp, ["--version"]) {
      versions.ytdlp = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let ffmpeg = binaryLocated?.ffmpeg,
       let output = try? await Self.run(ffmpeg, ["-version"]) {
      // First line looks like "ffmpeg version 6.1.1 Copyright (c) ..." —
      // just the version token is worth showing.
      let firstLine = output.stdout.split(separator: "\n").first.map(String.init) ?? ""
      versions.ffmpeg = firstLine
        .replacingOccurrences(of: "ffmpeg version ", with: "")
        .split(separator: " ")
        .first
        .map(String.init)
    }
    return versions
  }

  // MARK: - Safe process invocation
  //
  // The same incremental-drain pattern `YtdlpRunner.run` uses, and for the
  // same reason — see that method's doc comment for the deadlock a
  // read-only-after-exit version of this had caused. Duplicated here in
  // full, rather than shared, so this file stays self-contained and adding
  // this unrelated feature can't risk the already-fixed, already-critical
  // `YtdlpRunner` path.

  private struct Output {
    let status: Int32
    let stdout: String
  }

  private static func run(_ executable: URL, _ arguments: [String]) async throws -> Output {
    try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      process.executableURL = executable
      process.arguments = arguments

      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe

      let stdoutAccumulator = UpdaterDataAccumulator()
      let stderrAccumulator = UpdaterDataAccumulator()

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
        if let trailing = try? stdoutPipe.fileHandleForReading.readToEnd(), !trailing.isEmpty {
          stdoutAccumulator.append(trailing)
        }
        if let trailing = try? stderrPipe.fileHandleForReading.readToEnd(), !trailing.isEmpty {
          stderrAccumulator.append(trailing)
        }
        continuation.resume(returning: Output(
          status: finished.terminationStatus,
          stdout: String(data: stdoutAccumulator.snapshot(), encoding: .utf8) ?? ""
        ))
      }

      do {
        try process.run()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}

private final class UpdaterDataAccumulator {
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
