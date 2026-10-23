import SwiftUI
import AppKit

/// Shown instead of the download queue whenever `BinaryLocator` can't find
/// both `yt-dlp` and `ffmpeg` — see `BinaryLocator`'s doc comment for why
/// Tubio asks the person to install these themselves (via Homebrew)
/// rather than silently fetching and running third-party binaries on its
/// own.
struct MissingToolsView: View {
  @ObservedObject var viewModel: DownloadQueueViewModel
  @State private var copied = false

  private let brewCommand = "brew install yt-dlp ffmpeg"

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "shippingbox")
        .font(.system(size: 44, weight: .regular))
        .foregroundStyle(Theme.accent)

      VStack(spacing: 6) {
        Text("Brakuje yt-dlp i/lub ffmpeg")
          .font(.title3.weight(.semibold))
        Text("Tubio nie pobiera ani nie uruchamia tych narzędzi samodzielnie — to świadoma decyzja (patrz README). Zainstaluj je raz przez Homebrew, a Tubio znajdzie je automatycznie.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: 420)

      HStack(spacing: 10) {
        Text(brewCommand)
          .font(.system(.body, design: .monospaced))
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        Button {
          let pasteboard = NSPasteboard.general
          pasteboard.clearContents()
          pasteboard.setString(brewCommand, forType: .string)
          copied = true
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
        } label: {
          Image(systemName: copied ? "checkmark" : "doc.on.doc")
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help("Kopiuj polecenie")
      }

      VStack(spacing: 8) {
        Text("Nie masz Homebrew?")
          .font(.caption)
          .foregroundStyle(.secondary)
        Button("Otwórz brew.sh") {
          if let url = URL(string: "https://brew.sh") {
            NSWorkspace.shared.open(url)
          }
        }
        .buttonStyle(.link)
        .font(.caption)
      }

      Button("Sprawdź ponownie") {
        viewModel.recheckTools()
      }
      .buttonStyle(.borderedProminent)
      .tint(Theme.accent)
      .padding(.top, 4)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
  }
}
