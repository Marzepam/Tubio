import SwiftUI
import AppKit

/// A plain modal sheet rather than a separate Settings scene — Tubio is
/// small enough that a full macOS Settings window would be overkill.
struct SettingsView: View {
  @ObservedObject var viewModel: DownloadQueueViewModel
  @StateObject private var updater = HomebrewUpdater()
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Ustawienia")
        .font(.title3.weight(.semibold))

      VStack(alignment: .leading, spacing: 6) {
        Text("Folder docelowy").font(.callout.weight(.medium))
        HStack {
          Text(viewModel.destinationDirectory.path)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Button("Zmień…") { chooseFolder() }
            .buttonStyle(.bordered)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Szablon nazwy pliku").font(.callout.weight(.medium))
        TextField("%(title)s.%(ext)s", text: $viewModel.filenameTemplate)
          .textFieldStyle(.roundedBorder)
        Text("Korzysta ze składni szablonów yt-dlp, np. %(title)s, %(ext)s, %(uploader)s.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Domyślna jakość").font(.callout.weight(.medium))
        Picker("", selection: $viewModel.defaultQuality) {
          Text("Najlepsza jakość").tag(QualityOption.best)
          Text("1080p").tag(QualityOption.height(1080))
          Text("720p").tag(QualityOption.height(720))
          Text("480p").tag(QualityOption.height(480))
          Text("Tylko audio (MP3)").tag(QualityOption.audioOnly)
        }
        .labelsHidden()
        .pickerStyle(.menu)
      }

      Toggle("Dołącz miniaturę do pliku", isOn: $viewModel.embedThumbnail)
      Toggle("Dołącz napisy, jeśli dostępne", isOn: $viewModel.embedSubtitles)

      HStack {
        Text("Maks. równoczesnych pobrań").font(.callout.weight(.medium))
        Spacer()
        Stepper(value: $viewModel.maxConcurrentDownloads, in: 1...5) {
          Text("\(viewModel.maxConcurrentDownloads)")
        }
        .frame(width: 100)
      }

      Divider().overlay(Theme.divider)

      updatesSection

      Divider().overlay(Theme.divider)

      HStack {
        Spacer()
        Button("Zamknij") { dismiss() }
          .buttonStyle(.borderedProminent)
          .tint(Theme.accent)
      }
    }
    .padding(24)
    .frame(width: 420)
    .background(Theme.background)
  }

  // MARK: - yt-dlp / ffmpeg updates
  //
  // The Homebrew-native equivalent of the analyzed original project's own
  // binary-update system — see `HomebrewUpdater`'s doc comment for why
  // this checks/updates through `brew` rather than porting that project's
  // signed-manifest downloader (Tubio has nothing of its own for such
  // a port to point at).

  @ViewBuilder
  private var updatesSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("yt-dlp / ffmpeg").font(.callout.weight(.medium))

      updateStatusLine

      HStack(spacing: 10) {
        Button("Sprawdź aktualizacje") {
          Task { await updater.checkForUpdates(binaryLocated: viewModel.tools) }
        }
        .buttonStyle(.bordered)
        .disabled(updater.isUpdating)

        if case .updatesAvailable = updater.status {
          Button("Zaktualizuj (brew upgrade)") {
            Task { await updater.upgrade(binaryLocated: viewModel.tools) }
          }
          .buttonStyle(.borderedProminent)
          .tint(Theme.accent)
          .disabled(updater.isUpdating)
        }

        if updater.isUpdating {
          ProgressView().controlSize(.small)
        }
      }
    }
  }

  @ViewBuilder
  private var updateStatusLine: some View {
    switch updater.status {
    case .unknown:
      Text("Nie sprawdzono jeszcze.")
        .font(.caption2).foregroundStyle(.secondary)
    case .checking:
      Text("Sprawdzanie…")
        .font(.caption2).foregroundStyle(.secondary)
    case .upToDate(let versions):
      Text(String(
        format: String(localized: "Aktualne — yt-dlp %@, ffmpeg %@.", comment: "Shown when yt-dlp/ffmpeg are both up to date, with their version strings"),
        versions.ytdlp ?? "?", versions.ffmpeg ?? "?"
      ))
      .font(.caption2).foregroundStyle(.secondary)
    case .updatesAvailable(let outdated, let versions):
      Text(String(
        format: String(localized: "Dostępna aktualizacja: %@ (obecnie yt-dlp %@, ffmpeg %@).", comment: "Shown when brew outdated reports yt-dlp and/or ffmpeg have an update available"),
        outdated.joined(separator: ", "), versions.ytdlp ?? "?", versions.ffmpeg ?? "?"
      ))
      .font(.caption2).foregroundStyle(Theme.accent)
    case .brewNotFound:
      Text("Nie znaleziono polecenia brew — yt-dlp/ffmpeg trzeba zaktualizować ręcznie (brew upgrade yt-dlp ffmpeg).")
        .font(.caption2).foregroundStyle(.secondary)
    case .error(let message):
      Text(String(format: String(localized: "Błąd sprawdzania: %@", comment: "Shown when the brew outdated/upgrade check itself failed to run"), message))
        .font(.caption2).foregroundStyle(.red)
    }
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = viewModel.destinationDirectory
    panel.prompt = String(localized: "Wybierz", comment: "Confirm button in the folder-choosing panel")
    if panel.runModal() == .OK, let url = panel.url {
      viewModel.destinationDirectory = url
    }
  }
}
