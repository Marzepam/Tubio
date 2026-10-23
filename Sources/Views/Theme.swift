import SwiftUI

/// The one place Tubio's accent color lives — matches the app icon's
/// lighter accent red (see `icon-source/gen_icon.py`), used consistently
/// across the window instead of each view picking its own red.
///
/// `background`/`cardBackground`/`divider` are all AppKit *system* colors
/// (`NSColor.windowBackgroundColor` & co.), not fixed white/black values —
/// that's what makes the window follow macOS's own light/dark appearance
/// automatically (including "Auto" in System Settings → Appearance, which
/// switches at sunset/sunrise) instead of being forced into one look
/// regardless of the system setting. No `.preferredColorScheme(...)`
/// override anywhere in the app is what lets that happen — see
/// `TubioApp.swift`.
enum Theme {
  static let accent = Color(red: 196.0 / 255, green: 30.0 / 255, blue: 58.0 / 255)
  static let accentDark = Color(red: 73.0 / 255, green: 16.0 / 255, blue: 48.0 / 255)
  static let background = Color(nsColor: .windowBackgroundColor)
  static let cardBackground = Color(nsColor: .controlBackgroundColor)
  static let divider = Color(nsColor: .separatorColor)
}
