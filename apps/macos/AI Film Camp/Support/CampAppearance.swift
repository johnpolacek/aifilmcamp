import AppKit
import CoreText
import SwiftUI

/// The website's editorial palette, sized for a native working environment.
/// Dynamic colors follow the existing app appearance preference, including system mode.
enum CampAppearance {
    static let accent = Color("AccentColor")
    static let actionFill = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let accentInk = Color(white: 0.09)
    static let canvas = neutral("CampCanvas", light: 1, dark: 0.04)
    static let surface = neutral("CampSurface", light: 0.98, dark: 0.075)
    static let inset = neutral("CampInset", light: 0.95, dark: 0.105)
    static let rule = neutral("CampRule", light: 0.83, dark: 0.20)
    static let radius: CGFloat = 6

    static func title(_ size: CGFloat = 24) -> Font {
        .custom("RethinkSans-Regular", size: size).weight(.bold)
    }

    static func label(_ size: CGFloat = 11) -> Font {
        .custom("JetBrainsMono-Regular", size: size)
    }

    private static func neutral(_ name: String, light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(white: isDark ? dark : light, alpha: 1)
        })
    }

    /// Local font registration happens once before SwiftUI constructs the first screen.
    static func registerFonts() {
        for name in ["RethinkSans", "JetBrainsMono"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
            else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

struct CampSectionLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(CampAppearance.label())
            .tracking(1)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct CampPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var isHovered = false

    private var isCompact: Bool { controlSize == .small || controlSize == .mini }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((isCompact ? Font.caption : Font.body).weight(.semibold))
            .padding(.horizontal, isCompact ? 10 : 14)
            .padding(.vertical, isCompact ? 5 : 9)
            .foregroundStyle(isEnabled ? CampAppearance.accentInk : Color.secondary)
            .background(
                isEnabled ? CampAppearance.actionFill.opacity(configuration.isPressed ? 0.78 : isHovered ? 0.9 : 1) : CampAppearance.inset,
                in: RoundedRectangle(cornerRadius: CampAppearance.radius)
            )
            .contentShape(RoundedRectangle(cornerRadius: CampAppearance.radius))
            .onHover { isHovered = $0 }
    }
}

extension View {
    func campPanel() -> some View {
        background(CampAppearance.surface, in: RoundedRectangle(cornerRadius: CampAppearance.radius))
            .overlay {
                RoundedRectangle(cornerRadius: CampAppearance.radius)
                    .strokeBorder(CampAppearance.rule, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
