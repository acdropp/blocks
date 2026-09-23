import SwiftUI

/// All colors for the redesigned UI live here. Light theme only for now —
/// adding a dark variant later means giving these values a dark case each
/// (e.g. switching to Color(light:dark:) or a scheme-aware computed
/// property), not rewriting the views that reference them.
enum Palette {
    /// The window's lavender backdrop, behind the section cards.
    static let background = Color(red: 238 / 255, green: 228 / 255, blue: 250 / 255)

    /// The title bar strip behind the traffic-light buttons — a touch
    /// darker than the window background below it.
    static let titleBar = Color(red: 213 / 255, green: 195 / 255, blue: 235 / 255)

    /// The white fill for task-row cards and the quick-add field.
    static let cardBackground = Color.white

    /// The hairline divider drawn between rows inside a merged card.
    static let cardDivider = Color(red: 0.88, green: 0.85, blue: 0.94)

    /// Section headings, the active sort column, and other violet accents.
    static let accent = Color(red: 0.46, green: 0.29, blue: 0.86)

    /// A light violet tint for hover chips.
    static let accentSubtle = Color(red: 0.91, green: 0.88, blue: 0.98)

    /// The background of a selected task row (title line only — an
    /// expanded description box stays white even when its task is
    /// selected).
    static let selectedRow = Color(red: 213 / 255, green: 195 / 255, blue: 235 / 255)

    /// The border on an unchecked task checkbox.
    static let checkboxBorder = Color(red: 179 / 255, green: 176 / 255, blue: 188 / 255)

    /// Primary and secondary text on white cards.
    static let textPrimary = Color(red: 0.16, green: 0.14, blue: 0.20)
    static let textSecondary = Color(red: 0.47, green: 0.45, blue: 0.53)

    /// A deeper, more saturated pink than the old dark-background version —
    /// this one needs to read clearly on a white card.
    static let lateTask = Color(red: 0.80, green: 0.13, blue: 0.36)
}
