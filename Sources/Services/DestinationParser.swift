import Foundation

/// How the original project actually learns the final downloaded file's
/// path — *not* a `--print after_move:...` flag (Tubio's first draft
/// invented that instead, which is why it behaved differently from the
/// real engine). It watches yt-dlp's own ordinary human-readable output
/// lines as they go by and keeps the highest-confidence match it's seen:
///
/// - `[download] <path> has already been downloaded` (yt-dlp skipped
///   because the file already exists) — confidence 65
/// - `[VideoRemuxer] Not remuxing media file "<path>"; already is in
///   target format` — confidence 90
/// - `[Merger] Merging formats into "<path>"` — confidence 80
/// - any `[<Tag>] Destination: <path>` line, confidence depending on the
///   tag: `VideoConvertor` 95, `VideoRemuxer` 90, `Merger`/`ExtractAudio`
///   70, `download` 60, anything else 50
///
/// This mirrors a real download's life cycle: yt-dlp first announces where
/// the *raw* stream(s) are landing (confidence 60), then — if there's
/// merging/remuxing/audio-extraction to do — announces the postprocessed
/// destination at higher confidence, so the last, most-confident line seen
/// is reliably the actual final file. Direct port of
/// `YtdlpProgressParser::try_destination` / `try_merger_destination` from
/// the analyzed original project.
enum DestinationParser {
  struct Match {
    let path: String
    let confidence: Int
  }

  static func parse(line: String) -> Match? {
    if let path = alreadyDownloadedPath(line) {
      return Match(path: path, confidence: 65)
    }
    if let path = remuxerAlreadyPath(line) {
      return Match(path: path, confidence: 90)
    }
    if let path = mergerDestination(line) {
      return Match(path: path, confidence: 80)
    }
    return genericDestination(line)
  }

  private static func alreadyDownloadedPath(_ line: String) -> String? {
    guard let rest = stripPrefix(line, "[download] ") else { return nil }
    guard let range = rest.range(of: " has already been downloaded") else { return nil }
    let path = String(rest[rest.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    return path.isEmpty ? nil : path
  }

  private static func remuxerAlreadyPath(_ line: String) -> String? {
    guard let rest = stripPrefix(line, "[VideoRemuxer] Not remuxing media file ") else { return nil }
    guard let firstQuote = rest.firstIndex(of: "\"") else { return nil }
    let afterFirst = rest[rest.index(after: firstQuote)...]
    guard let secondQuote = afterFirst.firstIndex(of: "\"") else { return nil }
    let path = String(afterFirst[afterFirst.startIndex..<secondQuote]).trimmingCharacters(in: .whitespaces)
    return path.isEmpty ? nil : path
  }

  private static func mergerDestination(_ line: String) -> String? {
    guard let rest = stripPrefix(line, "[Merger] Merging formats into") else { return nil }
    let path = rest.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return path.isEmpty ? nil : path
  }

  private static func genericDestination(_ line: String) -> Match? {
    guard let range = line.range(of: "Destination:") else { return nil }
    let path = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    guard !path.isEmpty else { return nil }

    let tag = extractTag(line)
    let confidence: Int
    switch tag {
    case "VideoConvertor": confidence = 95
    case "VideoRemuxer": confidence = 90
    case "Merger", "ExtractAudio": confidence = 70
    case "download": confidence = 60
    default: confidence = 50
    }
    return Match(path: path, confidence: confidence)
  }

  private static func extractTag(_ line: String) -> String {
    guard line.hasPrefix("["), let closeBracket = line.firstIndex(of: "]") else { return "unknown" }
    return String(line[line.index(after: line.startIndex)..<closeBracket])
  }

  private static func stripPrefix(_ line: String, _ prefix: String) -> Substring? {
    guard line.hasPrefix(prefix) else { return nil }
    return line.dropFirst(prefix.count)
  }
}
