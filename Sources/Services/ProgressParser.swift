import Foundation

/// Turns one `RAW|...` line (yt-dlp's `--progress-template` output — see
/// `YtdlpArgs.progressTemplate`) into a `DownloadProgress`. This is a direct
/// port of `YtdlpProgressParser::try_progress_update` from the analyzed
/// original project: same 9-field layout, same multi-tier fallback for
/// computing a percentage when yt-dlp hasn't settled on one yet (e.g. right
/// at the start of a fragmented download), same "drop the line if it
/// carries no usable signal at all" rule — rather than Tubio's own
/// simpler (and, per feedback, less reliable) percent-only parsing.
enum ProgressParser {
  /// Field order, matching `YtdlpArgs.progressTemplate` exactly:
  /// 0 percent, 1 _percent_str, 2 speed (bytes/s), 3 eta (s),
  /// 4 downloaded_bytes, 5 total_bytes, 6 total_bytes_estimate,
  /// 7 fragment_index, 8 fragment_count.
  static func parse(line: String) -> DownloadProgress? {
    guard let raw = stripPrefix(line, "RAW|") else { return nil }

    var parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    while parts.count < 9 { parts.append("") }

    let pctNum = parsePercent(parts[0])
    let pctStr = parsePercent(parts[1])
    let speed = parseDouble(parts[2])
    let eta = parseUInt(parts[3])
    let downloaded = parseUInt(parts[4])
    let total = parseUInt(parts[5])
    let estimate = parseUInt(parts[6])
    let fragIndex = parseUInt(parts[7])
    let fragCount = parseUInt(parts[8])

    var percentage: Double?
    if let pctNum {
      percentage = pctNum
    } else if let pctStr {
      percentage = pctStr
    } else if let t = total ?? estimate, let d = downloaded, t > 0 {
      percentage = (Double(d) / Double(t)) * 100
    } else if let i = fragIndex, let n = fragCount, n > 0 {
      percentage = (Double(i) / Double(n)) * 100
    }
    percentage = percentage.map { $0.isFinite ? min(max($0, 0), 100) : 0 }

    // Matches the original: a line with no percentage, no speed, and no ETA
    // carries no signal worth surfacing, so it's dropped rather than
    // producing a zeroed-out progress update.
    guard percentage != nil || speed != nil || eta != nil else { return nil }

    var progress = DownloadProgress()
    progress.percent = percentage ?? 0
    progress.downloadedBytes = downloaded.map(Int64.init)
    progress.totalBytes = (total ?? estimate).map(Int64.init)
    progress.speedBytesPerSecond = speed
    progress.etaSeconds = eta.map(Int.init)
    return progress
  }

  private static func stripPrefix(_ line: String, _ prefix: String) -> Substring? {
    guard line.hasPrefix(prefix) else { return nil }
    return line.dropFirst(prefix.count)
  }

  private static func parsePercent(_ s: String) -> Double? {
    let t = s.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "%"))
    guard !t.isEmpty, !t.lowercased().contains("na") else { return nil }
    return Double(t)
  }

  private static func parseDouble(_ s: String) -> Double? {
    let t = s.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty, !t.lowercased().contains("na") else { return nil }
    return Double(t)
  }

  private static func parseUInt(_ s: String) -> UInt64? {
    let t = s.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty, !t.lowercased().contains("na") else { return nil }
    // yt-dlp can emit a trailing ".0" on some fields even though they're
    // conceptually integers — fall back to parsing as a double and
    // truncating rather than failing the whole field.
    if let direct = UInt64(t) { return direct }
    if let asDouble = Double(t), asDouble >= 0 { return UInt64(asDouble) }
    return nil
  }
}
