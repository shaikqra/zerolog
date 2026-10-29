import CoreText
import SwiftUI
import UIKit

// ZeroLog's look: true black for OLED screens, data colours taken from competition weight plates,
// a scoreboard font for numbers and titles, and a font made for reading at a glance mid-set.
// Every colour and font the phone app uses comes from this file.

extension Color {
    static let base = Color(hex: 0x000000)
    static let surface = Color(hex: 0x111214)
    static let raised = Color(hex: 0x1B1C1F)
    static let line = Color(hex: 0x2B2C30)
    static let lineStrong = Color(hex: 0x3A3B3F)
    static let textPrimary = Color(hex: 0xF3F3F0)
    static let textSecondary = Color(hex: 0xA9AAA5)
    static let textTertiary = Color(hex: 0x8A8B86)
    /// Red plate: workouts and training. Always next to a word, never decoration.
    static let load = Color(hex: 0xFF5B4F)
    /// Green plate: done.
    static let done = Color(hex: 0x3FD68A)

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    /// Numbers and big titles: Big Shoulders Display, like a gym scoreboard.
    static func score(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("BigShouldersDisplay-ExtraBold", size: size, relativeTo: style)
    }

    /// Everything else: Atkinson Hyperlegible.
    static func ui(_ size: CGFloat = 17, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(bold ? "AtkinsonHyperlegible-Bold" : "AtkinsonHyperlegible-Regular", size: size, relativeTo: style)
    }
}

enum Style {
    /// Loads the bundled fonts and styles the navigation and tab bars, which SwiftUI can't reach. Call once at launch.
    static func apply() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }

        let white = UIColor(Color.textPrimary)
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = .black
        nav.shadowColor = .clear
        if let title = UIFont(name: "BigShouldersDisplay-ExtraBold", size: 48) {
            nav.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: title),
                                            .foregroundColor: white]
        }
        if let title = UIFont(name: "AtkinsonHyperlegible-Bold", size: 17) {
            nav.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: title),
                                       .foregroundColor: white]
        }
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Color.surface)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

/// The one main action on a screen: white, black text.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.ui(18, bold: true))
                .foregroundStyle(Color.base)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color.textPrimary, in: RoundedRectangle(cornerRadius: 14))
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
        }
    }
}

/// A secondary action, such as Undo: outlined, no fill.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(16, bold: true))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.lineStrong))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A section heading in sentence case. iOS shows plain header strings in capitals, so headers use this.
struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.ui(17, bold: true))
            .foregroundStyle(Color.textPrimary)
            .textCase(nil)
    }
}

extension View {
    /// A list or form on the black page. Give each section `.listRowBackground(Color.surface)`.
    func darkList() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.base)
    }
}
