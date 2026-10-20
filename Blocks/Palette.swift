import SwiftUI
import AppKit

/// The app's own light/dark setting — independent of the Mac's system Dark
/// Mode. Switched via the sun/moon button, stored so it's remembered next
/// launch, and read by both windows (ContentView and SettingsView) via the
/// same "appTheme" AppStorage key.
enum AppTheme: String {
    case light, dark

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var icon: String { self == .dark ? "moon.fill" : "sun.max.fill" }
    var toggled: AppTheme { self == .dark ? .light : .dark }
}

/// All colors for the UI live here, each one a dynamic Color that resolves
/// to its light or dark value based on the view's effective appearance —
/// which `.preferredColorScheme(AppTheme...)` on each window sets according
/// to the stored AppTheme, not the system's actual Dark Mode setting. Views
/// never check the theme themselves; they just reference `Palette.x`.
enum Palette {
    /// The window's lavender (light) / deep violet (dark) backdrop, behind
    /// the section cards.
    static let background = dynamic(
        light: (238, 228, 250),
        dark: (24, 20, 32)
    )

    /// The title bar strip behind the traffic-light buttons — a touch
    /// darker than the window background below it, in both themes.
    static let titleBar = dynamic(
        light: (213, 195, 235),
        dark: (50, 42, 66)
    )

    /// The card fill for task rows and the quick-add field — white in
    /// light mode, a lighter charcoal-violet than the background in dark
    /// mode (so cards still read as a distinct surface).
    static let cardBackground = dynamic(
        light: (255, 255, 255),
        dark: (42, 36, 54)
    )

    /// The hairline divider drawn between rows inside a merged card.
    static let cardDivider = dynamic(
        light: (224, 217, 240),
        dark: (64, 56, 78)
    )

    /// Section headings, the active sort column, and other violet accents.
    static let accent = dynamic(
        light: (117, 74, 219),
        dark: (178, 142, 255)
    )

    /// A light violet tint for hover chips.
    static let accentSubtle = dynamic(
        light: (232, 224, 250),
        dark: (58, 48, 82)
    )

    /// The background of a selected task row (title line only — an
    /// expanded description box stays the card color even when its task
    /// is selected).
    static let selectedRow = dynamic(
        light: (213, 195, 235),
        dark: (76, 60, 102)
    )

    /// The border on an unchecked task checkbox.
    static let checkboxBorder = dynamic(
        light: (179, 176, 188),
        dark: (120, 112, 136)
    )

    /// Primary and secondary text on cards.
    static let textPrimary = dynamic(
        light: (41, 36, 51),
        dark: (236, 232, 244)
    )
    static let textSecondary = dynamic(
        light: (120, 115, 135),
        dark: (168, 160, 182)
    )

    /// Flags a late task's title, scheduled time, and list name — a
    /// deeper rose in light mode (reads on white), a brighter one in dark
    /// mode (reads on a dark card).
    static let lateTask = dynamic(
        light: (204, 33, 92),
        dark: (255, 120, 158)
    )

    /// Builds a Color that resolves live to one RGB triple or the other
    /// based on the current effective appearance (light vs. dark), via a
    /// dynamic NSColor. This is what lets every view just say
    /// `Palette.someColor` once and have it automatically track whichever
    /// theme is active, instead of each call site branching on it.
    private static func dynamic(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        })
    }
}
