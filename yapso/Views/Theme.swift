import SwiftUI
import UIKit

/// Paper and ink, with one warm accent. Text stays `.primary`/`.secondary` so it follows light and dark.
extension Color {
    /// Every screen's background: warm off-white, or warm near-black in dark mode.
    static let paper = Color(light: 0xF6F4EF, dark: 0x121110)
    /// Cards and grouped rows, a step up from the paper.
    static let card = Color(light: 0xFFFFFF, dark: 0x1D1B19)
    /// Card outlines.
    static let hairline = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.07) })
    /// The one accent: the streak, the clocks, the ratings. Used sparingly.
    static let ember = Color(light: 0xD9542A, dark: 0xF0703F)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

extension Font {
    /// Serif headline for topics and big statements (New York).
    static let display = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let displaySmall = Font.system(.title, design: .serif).weight(.semibold)
}

extension View {
    /// A card on the paper: lifted fill and a hairline edge instead of a grey box.
    func cardBackground(cornerRadius: CGFloat = 16) -> some View {
        background(Color.card, in: .rect(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.hairline))
    }
}

/// One of the ink line drawings, drawn in the current text color so it works on paper and in dark mode.
struct Illustration: View {
    let name: String
    var height: CGFloat

    @State private var shown = false

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(.primary.opacity(0.9))
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.96)
            .onAppear { withAnimation(.smooth(duration: 0.8)) { shown = true } }
            .accessibilityHidden(true)
    }
}

enum Theme {
    /// UIKit-drawn chrome (navigation titles, lists, forms) that SwiftUI modifiers don't reach.
    static func applyAppearance() {
        let serif = { (style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont in
            let base = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
            let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
            return UIFont(descriptor: descriptor, size: 0)
        }
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [.font: serif(.largeTitle, .semibold)]
        nav.titleTextAttributes = [.font: serif(.headline, .semibold)]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.largeTitleTextAttributes = nav.largeTitleTextAttributes
        scrolled.titleTextAttributes = nav.titleTextAttributes
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
    }
}
