import SwiftUI

/// One row in the queue list — mirrors, in spirit, the "clip row" visual
/// weight Movi uses for its timeline items: a thumbnail, a title, and a
/// slim status/progress strip, all on one card.
struct DownloadCardView: View {
  @ObservedObject var viewModel: DownloadQueueViewModel
  @ObservedObject var item: DownloadItem

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      thumbnail

      VStack(alignment: .leading, spacing: 6) {
        Text(item.displayTitle)
          .font(.callout.weight(.medium))
          .lineLimit(2)
          .truncationMode(.tail)

        statusRow

        if item.state == .queued || item.state == .fetchingInfo {
          qualityPicker
        }

        if item.state == .downloading || item.state == .paused {
          progressRow
        }

        if item.state == .failed, let message = item.errorMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(2)
        }
      }

      Spacer(minLength: 8)

      actionButtons
    }
    .padding(12)
    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  // MARK: - Pieces

  @ViewBuilder
  private var thumbnail: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Theme.cardBackground)
      if let thumbnailURLString = item.mediaInfo?.thumbnail,
         let thumbnailURL = URL(string: thumbnailURLString) {
        AsyncImage(url: thumbnailURL) { phase in
          switch phase {
          case .success(let image):
            image.resizable().aspectRatio(contentMode: .fill)
          default:
            Image(systemName: "play.rectangle")
              .font(.title2)
              .foregroundStyle(.primary)
          }
        }
      } else {
        Image(systemName: item.state == .fetchingInfo ? "hourglass" : "play.rectangle")
          .font(.title2)
          .foregroundStyle(.primary)
      }
    }
    // Bigger than the first draft's 96×60 — easier to recognize a video at
    // a glance in a list of several queued downloads.
    .frame(width: 176, height: 110)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  @ViewBuilder
  private var statusRow: some View {
    HStack(spacing: 6) {
      statusBadge
      if let duration = item.mediaInfo?.duration {
        Text(formattedDuration(duration))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var statusBadge: some View {
    switch item.state {
    case .fetchingInfo:
      Label("Wczytywanie informacji…", systemImage: "arrow.triangle.2.circlepath")
        .font(.caption).foregroundStyle(.secondary)
    case .queued:
      Label("W kolejce", systemImage: "clock")
        .font(.caption).foregroundStyle(.secondary)
    case .downloading:
      Label("Pobieranie…", systemImage: "arrow.down.circle")
        .font(.caption).foregroundStyle(Theme.accent)
    case .paused:
      Label("Wstrzymano", systemImage: "pause.circle")
        .font(.caption).foregroundStyle(.secondary)
    case .completed:
      Label("Ukończono", systemImage: "checkmark.circle.fill")
        .font(.caption).foregroundStyle(.green)
    case .failed:
      Label("Błąd", systemImage: "exclamationmark.triangle.fill")
        .font(.caption).foregroundStyle(.red)
    case .cancelled:
      Label("Anulowano", systemImage: "xmark.circle")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var qualityPicker: some View {
    Picker("Jakość", selection: Binding(
      get: { item.selectedQuality },
      set: { item.selectedQuality = $0 }
    )) {
      ForEach(qualityOptions) { option in
        Text(option.label).tag(option)
      }
    }
    .labelsHidden()
    .pickerStyle(.menu)
    .font(.caption)
    .frame(maxWidth: 180)
  }

  private var qualityOptions: [QualityOption] {
    guard let info = item.mediaInfo else { return [.best] }
    var options: [QualityOption] = [.best]
    options.append(contentsOf: info.availableHeights.map { QualityOption.height($0) })
    if info.hasAudio {
      options.append(.audioOnly)
    }
    return options
  }

  @ViewBuilder
  private var progressRow: some View {
    VStack(alignment: .leading, spacing: 3) {
      ProgressView(value: item.progress.percent, total: 100)
        .tint(Theme.accent)
      HStack(spacing: 6) {
        Text(String(format: String(localized: "%d%%", comment: "Download progress percentage, e.g. 42%"), Int(item.progress.percent)))
        if let speed = item.progress.speedBytesPerSecond {
          Text(String(format: String(localized: "· %@", comment: "Bullet + download speed, e.g. · 3.2 MB/s"), formattedSpeed(speed)))
        }
        if let eta = item.progress.etaSeconds {
          Text(String(format: String(localized: "· pozostało %@", comment: "Bullet + remaining time, e.g. · pozostało 2 min 10 s"), formattedETA(eta)))
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var actionButtons: some View {
    HStack(spacing: 6) {
      switch item.state {
      case .queued:
        Button {
          viewModel.start(item)
        } label: {
          Image(systemName: "arrow.down.circle")
        }
        .help("Pobierz teraz")
      case .downloading:
        Button {
          viewModel.pause(item)
        } label: {
          Image(systemName: "pause.circle")
        }
        .help("Wstrzymaj")
        Button {
          viewModel.cancel(item)
        } label: {
          Image(systemName: "xmark.circle")
        }
        .help("Anuluj")
      case .paused:
        Button {
          viewModel.resume(item)
        } label: {
          Image(systemName: "play.circle")
        }
        .help("Wznów")
        Button {
          viewModel.cancel(item)
        } label: {
          Image(systemName: "xmark.circle")
        }
        .help("Anuluj")
      case .failed:
        Button {
          viewModel.retry(item)
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .help("Spróbuj ponownie")
      case .completed:
        Button {
          viewModel.revealInFinder(item)
        } label: {
          Image(systemName: "folder")
        }
        .help("Pokaż w Finderze")
        Button {
          viewModel.openFile(item)
        } label: {
          Image(systemName: "play.circle")
        }
        .help("Otwórz")
      default:
        EmptyView()
      }

      Button {
        viewModel.remove(item)
      } label: {
        Image(systemName: "trash")
      }
      .help("Usuń z listy")
    }
    .buttonStyle(.plain)
    // Neutral, mode-adaptive `.primary` for the whole row — same system
    // label color the Settings gear icon already uses (dark glyph in Light
    // appearance, light glyph in Dark appearance), not the brand-red accent
    // these used to share.
    .foregroundStyle(.primary)
    .font(.system(size: 15))
  }

  // MARK: - Formatting

  private func formattedDuration(_ seconds: Double) -> String {
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
      return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%d:%02d", m, s)
  }

  private func formattedSpeed(_ bytesPerSecond: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
  }

  private func formattedETA(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    if m > 0 {
      return String(format: String(localized: "%d min %d s", comment: "Minutes and seconds remaining, e.g. 2 min 10 s"), m, s)
    }
    return String(format: String(localized: "%d s", comment: "Seconds remaining only"), s)
  }
}
