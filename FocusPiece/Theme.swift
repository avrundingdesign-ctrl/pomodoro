import SwiftUI

// MARK: - Design Tokens
// All values are taken verbatim from the FocusPiece hi-fi design handoff.
// Colors, type scale, radii, shadows and spacing are binding ("verbindlich").

enum Theme {

    // MARK: Colors
    enum Palette {
        static let paper       = Color(hex: 0xF3EFE7) // App background
        static let surface     = Color(hex: 0xFBF9F4) // List / setting cards
        static let surface2     = Color(hex: 0xEFE7DA) // Icon badges, info cards, chips
        static let ink         = Color(hex: 0x2A251F) // Primary text
        static let ink2        = Color(hex: 0x211E1A) // Headings / values
        static let muted       = Color(hex: 0x6F675C) // Body text
        static let muted2      = Color(hex: 0x8C8479) // Captions, labels
        static let muted3      = Color(hex: 0xA39A8C) // Group labels, disabled
        static let muted3Soft  = Color(hex: 0xB3AA9C)
        static let accent      = Color(hex: 0xC25A35) // Terracotta — buttons, active states
        static let hairline    = Color(hex: 0xE6E0D4) // Dividers, borders
        static let hairline2   = Color(hex: 0xECE5D8)
        static let hairline3   = Color(hex: 0xEFE8DB)
        static let cardBorder  = Color(hex: 0xE9E2D5) // Chip / card border
        static let toggleOff   = Color(hex: 0xD8D2C6) // Inactive switch track
        static let artistInk   = Color(hex: 0x7D7468) // Italic artist caption
        static let bodySoft    = Color(hex: 0x5F574C)
        static let dotInactive = Color(hex: 0xCFC7B8) // Onboarding page dots
        static let progressTrack = Color(hex: 0xE3DCCD)
        static let circleButton  = Color(hex: 0xECE5D8) // Round back/pause buttons

        /// Paper veil drawn over hidden reveal tiles — rgba(243,239,231,0.22)
        static let revealVeil  = Color(hex: 0xF3EFE7).opacity(0.22)
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

// MARK: - Color hex helper
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
