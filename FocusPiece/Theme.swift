import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Design Tokens
// All values are taken verbatim from the FocusPiece hi-fi design handoff.
// Colors, type scale, radii, shadows and spacing are binding ("verbindlich").

enum Theme {

    // MARK: Colors
    // Light values are the binding handoff tokens; dark values are warm,
    // gallery-at-night counterparts. Resolved per trait via dynamic UIColor.
    enum Palette {
        static let paper       = Color(light: 0xF3EFE7, dark: 0x1C1915) // App background
        static let surface     = Color(light: 0xFBF9F4, dark: 0x26221B) // List / setting cards
        static let surface2    = Color(light: 0xEFE7DA, dark: 0x2E2820) // Icon badges, info cards, chips
        static let ink         = Color(light: 0x2A251F, dark: 0xEDE7DB) // Primary text
        static let ink2        = Color(light: 0x211E1A, dark: 0xF2EDE2) // Headings / values
        static let muted       = Color(light: 0x6F675C, dark: 0xA79D8F) // Body text
        static let muted2      = Color(light: 0x8C8479, dark: 0x948B7E) // Captions, labels
        static let muted3      = Color(light: 0xA39A8C, dark: 0x7A7164) // Group labels, disabled
        static let muted3Soft  = Color(light: 0xB3AA9C, dark: 0x6B6357)
        static let accent      = Color(light: 0xC25A35, dark: 0xD06A43) // Terracotta — buttons, active states
        static let hairline    = Color(light: 0xE6E0D4, dark: 0x353028) // Dividers, borders
        static let hairline2   = Color(light: 0xECE5D8, dark: 0x322D25)
        static let hairline3   = Color(light: 0xEFE8DB, dark: 0x2F2A23)
        static let cardBorder  = Color(light: 0xE9E2D5, dark: 0x3A342B) // Chip / card border
        static let toggleOff   = Color(light: 0xD8D2C6, dark: 0x4A443A) // Inactive switch track
        static let artistInk   = Color(light: 0x7D7468, dark: 0x9A9083) // Italic artist caption
        static let bodySoft    = Color(light: 0x5F574C, dark: 0xC4BBAC)
        static let dotInactive = Color(light: 0xCFC7B8, dark: 0x4E473C) // Onboarding page dots
        static let progressTrack = Color(light: 0xE3DCCD, dark: 0x3A342B)
        static let circleButton  = Color(light: 0xECE5D8, dark: 0x322D25) // Round back/pause buttons

        /// Paper veil drawn over hidden reveal tiles — rgba(paper, 0.22)
        static let revealVeil  = Color(light: 0xF3EFE7, dark: 0x1C1915).opacity(0.22)
    }

    // MARK: Typography
    // Custom fonts are bundled (Resources/Fonts) and registered via Info.plist.
    enum Font {
        // Serif — Newsreader
        static func serif(_ size: CGFloat, weight: SerifWeight = .regular) -> SwiftUI.Font {
            .custom(weight.psName, size: size)
        }
        static func serifItalic(_ size: CGFloat) -> SwiftUI.Font {
            .custom("Newsreader-Italic", size: size)
        }
        // Sans — Hanken Grotesk
        static func sans(_ size: CGFloat, weight: SansWeight = .regular) -> SwiftUI.Font {
            .custom(weight.psName, size: size)
        }

        enum SerifWeight { case light, regular, medium
            var psName: String {
                switch self {
                case .light:   return "Newsreader-Light"
                case .regular: return "Newsreader-Regular"
                case .medium:  return "Newsreader-Medium"
                }
            }
        }
        enum SansWeight { case regular, medium, semibold, bold
            var psName: String {
                switch self {
                case .regular:  return "HankenGrotesk-Regular"
                case .medium:   return "HankenGrotesk-Medium"
                case .semibold: return "HankenGrotesk-SemiBold"
                case .bold:     return "HankenGrotesk-Bold"
                }
            }
        }
    }

    // MARK: Radius
    enum Radius {
        static let primaryButton: CGFloat = 18
        static let artCard:       CGFloat = 26
        static let galleryTile:   CGFloat = 18
        static let settingCard:   CGFloat = 18
        static let iconBadge:     CGFloat = 15
        static let durationChip:  CGFloat = 18
    }

    // MARK: Spacing
    enum Pad {
        static let screenH: CGFloat = 28   // default horizontal inset
    }

    // MARK: Adaptive layout (iPad)
    // On regular-width screens content sits in a centered, readable column
    // instead of stretching the phone layout across the full canvas
    // (App Review Guideline 4, iPad Air 11"). Both caps are wider than any
    // iPhone, so they are no-ops on compact devices.
    enum Layout {
        static let contentMaxWidth: CGFloat = 560   // text & control column
        static let galleryMaxWidth: CGFloat = 920   // grid screens
    }
}

// MARK: - Color hex helpers
extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue:  Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    /// Dynamic color that resolves per light/dark trait.
    ///
    /// watchOS has no `UIColor(dynamicProvider:)` — and no light mode either:
    /// the watch face is always dark, so the dark value is the only one that
    /// can ever apply. That lets the whole palette above carry over unchanged.
    init(light: UInt, dark: UInt) {
        #if os(watchOS)
        self.init(hex: dark)
        #else
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red:   CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue:  CGFloat(hex & 0xFF) / 255.0,
                alpha: 1)
        })
        #endif
    }
}

// MARK: - Reusable text styles
extension View {
    /// Eyebrow / label: 12 / 600 / 0.16–0.24em / uppercase, usually accent.
    func eyebrow(color: Color = Theme.Palette.accent, tracking: CGFloat = 2.2) -> some View {
        self.font(Theme.Font.sans(12, weight: .semibold))
            .textCase(.uppercase)
            .tracking(tracking)
            .foregroundStyle(color)
    }

    /// Caps the view at a readable column width and centers it horizontally.
    /// iPhones are narrower than every cap, so this only affects iPad.
    func contentColumn(_ maxWidth: CGFloat = Theme.Layout.contentMaxWidth) -> some View {
        self.frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
