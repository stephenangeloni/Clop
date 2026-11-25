import AppKit
import Lowtech
import SwiftUI

enum Palette {
    static let brandAmber = Color(.sRGB, red: 1.0, green: 0.690, blue: 0.125)
    static let brandAmberDeep = Color(.sRGB, red: 0.604, green: 0.357, blue: 0.0)

    static let saving = Color(light: brandAmberDeep, dark: brandAmber)
    static let savingOnThumbnail = brandAmber
    static let growth = Color(light: rgb(0.784, 0.157, 0.235), dark: rgb(1.0, 0.420, 0.478))
    static let growthOnThumbnail = rgb(1.0, 0.420, 0.478)

    static let ink = Color(light: rgb(0.24, 0.17, 0.09), dark: rgb(0.98, 0.93, 0.84))

    static let image = Color(light: rgb(0.122, 0.373, 0.749), dark: rgb(0.416, 0.659, 1.0))
    static let video = Color(light: rgb(0.722, 0.196, 0.478), dark: rgb(1.0, 0.494, 0.753))
    static let audio = Color(light: rgb(0.180, 0.490, 0.310), dark: rgb(0.435, 0.816, 0.549))
    static let pdf = Color(light: rgb(0.761, 0.271, 0.176), dark: rgb(1.0, 0.541, 0.439))

    static let dismissFill = Color(light: rgb(1.0, 0.89, 0.89), dark: rgb(0.32, 0.14, 0.14))
    static let dismissFillHovered = Color(light: rgb(1.0, 0.82, 0.82), dark: rgb(0.42, 0.17, 0.17))

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r, green: g, blue: b)
    }
}

/// Warm, cosy colour theme for the pipeline editors: Rosé Pine Dawn in light mode and a Terracotta
/// Dark palette (warm clay accents on a dark-brown base) in dark mode. The editor background is the
/// anchor; the syntax accents are tuned to read well on it.
enum PipelineTheme {
    static var editorBackground: Color {
        adaptive(light: lightBase, dark: darkBase)
    }

    static var topBarBackground: Color {
        adaptive(light: lightChrome, dark: darkChrome)
    }

    static func text(dark: Bool) -> NSColor {
        dark ? darkText : lightText
    }
    static func muted(dark: Bool) -> NSColor {
        dark ? darkMuted : lightMuted
    }
    static func invalid(dark: Bool) -> NSColor {
        dark ? darkRust : lightLove
    }

    static func category(_ category: StepCategory, dark: Bool) -> NSColor {
        switch category {
        case .processing: dark ? darkPine : lightPine
        case .fileOperation: dark ? darkGold : lightGold
        case .filter: dark ? darkRose : lightRose
        case .mediaSpecific: dark ? darkLove : lightLove
        case .action: dark ? darkIris : lightIris
        }
    }

    static func categoryColor(_ category: StepCategory) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            Self.category(category, dark: ap.bestMatch(from: [.darkAqua, .vibrantDark]) != nil)
        })
    }

    private static let lightBase = displayP3(0xFAF4ED)
    private static let lightChrome = displayP3(0xFFFEFC)
    private static let lightText = displayP3(0x464261)
    private static let lightMuted = displayP3(0x797593)
    private static let lightPine = displayP3(0x286983)
    private static let lightGold = displayP3(0xEA9D34)
    private static let lightRose = displayP3(0xD7827E)
    private static let lightLove = displayP3(0xB4637A)
    private static let lightIris = displayP3(0x907AA9)

    private static let darkBase = displayP3(0x241F1D)
    private static let darkChrome = displayP3(0x141313)
    private static let darkText = displayP3(0xECE0D4)
    private static let darkMuted = displayP3(0xA89484)
    private static let darkPine = displayP3(0x6FB0C9)
    private static let darkGold = displayP3(0xF6C177)
    private static let darkRose = displayP3(0xE39B96)
    private static let darkLove = displayP3(0xEB6F92)
    private static let darkIris = displayP3(0xC4A7E7)
    private static let darkRust = displayP3(0xC4604F)

    /// Colours are defined in Display P3 so they sample as the exact hex on wide-gamut Mac displays.
    /// An sRGB-defined colour reads ~1 level off when the colour meter shows display-native values.
    private static func displayP3(_ hex: UInt32) -> NSColor {
        NSColor(displayP3Red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? dark : light
        })
    }
}

private struct OpaqueWhenReducingTransparency<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let fill: Color
    let shape: S

    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency {
                shape.fill(fill)
            }
        }
    }
}

extension View {
    func opaqueWhenReducingTransparency(_ fill: Color, in shape: some Shape) -> some View {
        modifier(OpaqueWhenReducingTransparency(fill: fill, shape: shape))
    }
}

enum TextSize {
    static let caption = NSFont.preferredFont(forTextStyle: .caption1).pointSize
    static let subheadline = NSFont.preferredFont(forTextStyle: .subheadline).pointSize
    static let callout = NSFont.preferredFont(forTextStyle: .callout).pointSize
    static let body = NSFont.preferredFont(forTextStyle: .body).pointSize
    static let title3 = NSFont.preferredFont(forTextStyle: .title3).pointSize
    static let title2 = NSFont.preferredFont(forTextStyle: .title2).pointSize

    static let cardBadge: CGFloat = 9
    static let display: CGFloat = 48
    static let wordmark: CGFloat = 64
}

enum IconSize {
    static let medium: CGFloat = 20
    static let large: CGFloat = 30
    static let xlarge: CGFloat = 40
    static let hero: CGFloat = 64
}

enum Radius {
    static let hairline: CGFloat = 2
    static let small: CGFloat = 4
    static let medium: CGFloat = 6
    static let large: CGFloat = 8
    static let xlarge: CGFloat = 10
    static let panel: CGFloat = 16
    static let card: CGFloat = 22
}

enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 8
    static let l: CGFloat = 12
    static let xl: CGFloat = 16
    static let window: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 48
}
