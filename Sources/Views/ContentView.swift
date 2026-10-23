import SwiftUI
import AppKit

/// The whole app, window-wise: one white window, a header with the
/// Tubio brand mark, a URL field to add links, and the download queue
/// below — no tabs, no multi-window document model like Movi, since there's
/// only ever one list of downloads to manage.
struct ContentView: View {
  @StateObject private var viewModel = DownloadQueueViewModel()
  @State private var urlField: String = ""
  @State private var showingSettings = false

  var body: some View {
    VStack(spacing: 0) {
      header

      Divider().overlay(Theme.divider)

      if viewModel.tools == nil {
        MissingToolsView(viewModel: viewModel)
      } else {
        addURLRow

        Divider().overlay(Theme.divider)

        queueList
      }
    }
    .background(Theme.background)
    .frame(minWidth: 560, idealWidth: 640, minHeight: 420, idealHeight: 620)
    .sheet(isPresented: $showingSettings) {
      SettingsView(viewModel: viewModel)
    }
    .alert(
      "Coś nie zagrało",
      isPresented: Binding(
        get: { viewModel.globalErrorMessage != nil },
        set: { if !$0 { viewModel.globalErrorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) { viewModel.globalErrorMessage = nil }
    } message: {
      Text(viewModel.globalErrorMessage ?? "")
    }
    .alert(
      "Witaj w Tubio",
      isPresented: $viewModel.showFirstLaunchToolsAlert
    ) {
      Button("OK") { }
    } message: {
      Text("Do pobierania wideo Tubio potrzebuje yt-dlp i ffmpeg zainstalowanych przez Homebrew. Na następnym ekranie znajdziesz gotowe do skopiowania polecenie instalacyjne.")
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 10) {
      Image("BrandMark")
        .resizable()
        .frame(width: 26, height: 26)

      Text("Tubio")
        .font(.title3.weight(.semibold))

      Spacer()

      Button {
        showingSettings = true
      } label: {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.plain)
      // `.primary` (not `.secondary`) so this tracks the system label color
      // properly: a dark icon in Light appearance, a light icon in Dark
      // appearance — `.secondary` is adaptive too, but stays a muted gray
      // in both, which read as low-contrast/washed-out against the window
      // background in one of the two modes.
      .foregroundStyle(.primary)
      .help("Ustawienia")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  // MARK: - Add URL

  private var addURLRow: some View {
    HStack(spacing: 8) {
      TextField("Wklej adres filmu…", text: $urlField)
        .textFieldStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onSubmit(addFromField)

      Button {
        if let clipboardString = NSPasteboardString(), urlField.isEmpty {
          urlField = clipboardString
        } else {
          addFromField()
        }
      } label: {
        Image(systemName: urlField.isEmpty ? "doc.on.clipboard" : "plus.circle.fill")
      }
      .buttonStyle(.plain)
      // Same neutral, mode-adaptive `.primary` as the rest of the app's
      // icon buttons now use — see `DownloadCardView.actionButtons`.
      .foregroundStyle(.primary)
      .font(.system(size: 18))
      .help(urlField.isEmpty ? "Wklej ze schowka" : "Dodaj do kolejki")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private func addFromField() {
    guard !urlField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    viewModel.addURL(urlField)
    urlField = ""
  }

  private func NSPasteboardString() -> String? {
    NSPasteboard.general.string(forType: .string)
  }

  // MARK: - Queue

  @ViewBuilder
  private var queueList: some View {
    if viewModel.items.isEmpty {
      emptyState
    } else {
      ScrollView {
        VStack(spacing: 8) {
          ForEach(viewModel.items) { item in
            DownloadCardView(viewModel: viewModel, item: item)
          }
        }
        .padding(16)
      }

      Divider().overlay(Theme.divider)

      HStack {
        Spacer()
        Button("Wyczyść ukończone") {
          viewModel.clearCompleted()
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .disabled(!viewModel.items.contains { $0.state == .completed })
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Spacer()
      Image(systemName: "arrow.down.to.line.circle")
        .font(.system(size: 36))
        .foregroundStyle(.secondary)
      Text("Wklej adres filmu powyżej, aby zacząć")
        .font(.callout)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
