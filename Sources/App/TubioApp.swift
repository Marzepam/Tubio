import AppKit
import SwiftUI

@main
struct TubioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // No `.preferredColorScheme(...)` override on purpose — the
                // window follows macOS's own Appearance setting (Light,
                // Dark, or Auto/sunset-sunrise) instead of being forced into
                // one look. See `Theme.swift`.
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            TubioCommands()
        }
    }
}

struct TubioCommands: Commands {
    var body: some Commands {
        // The window has no File-menu-worthy document concept (nothing to
        // open/save as a file — URLs are added via the in-window text
        // field), so the New Item slot is removed rather than left wired to
        // a meaningless "New Window".
        CommandGroup(replacing: .newItem) { }

        CommandGroup(replacing: .appInfo) {
            Button("O Tubio") {
                AboutPanel.show()
            }
        }
    }
}

/// Standard macOS About panel — author + version, no license text, same
/// pattern Movi uses.
enum AboutPanel {
    static func show() {
        let authorParagraph = NSMutableParagraphStyle()
        authorParagraph.alignment = .center

        let credits = NSAttributedString(
            string: String(localized: "Made by Marcin Lipiński\nPobieranie realizują yt-dlp i ffmpeg (Homebrew)", comment: "About panel credits: author line + 'downloads are handled by yt-dlp and ffmpeg (Homebrew)' line"),
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .paragraphStyle: authorParagraph
            ]
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "1.0",
            .credits: credits
        ])
    }
}
