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

enum TextSize {
    static let micro: CGFloat = 9
    static let caption: CGFloat = 10
    static let subheadline: CGFloat = 11
    static let callout: CGFloat = 12
    static let body: CGFloat = 13
    static let title3: CGFloat = 15
    static let title2: CGFloat = 17
    static let title1: CGFloat = 22
    static let largeTitle: CGFloat = 26
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
