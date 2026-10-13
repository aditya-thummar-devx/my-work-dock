import SwiftUI
import AppKit
import CoreText

enum Typo {
    /// Snapshot harness only: renders UI text in Geist because the reference PNGs were captured without SF Pro.
    static var uiFamily: String?

    /// SF Pro Text (system) for UI.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let uiFamily { return .custom(uiFamily, size: size).weight(weight) }
        return .system(size: size, weight: weight)
    }

    /// Bricolage Grotesque 800 for display titles and numbers. Chrome auto-sets the optical-size axis to the
    /// font size, so the variation is set explicitly (opsz = size, clamped to the font's 12...96 range).
    static func display(_ size: CGFloat) -> Font {
        func tag(_ s: String) -> NSNumber { NSNumber(value: s.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }) }
        let variation: [NSNumber: Double] = [tag("opsz"): Double(min(max(size, 12), 96)), tag("wght"): 800, tag("wdth"): 100]
        let desc = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: "Bricolage Grotesque",
            kCTFontVariationAttribute: variation,
        ] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(desc, size, nil))
    }

    /// Extra line spacing that makes a UI-font paragraph `lineHeight × size` tall per line, like CSS `line-height: 1.4`.
    /// SwiftUI only offers additive spacing on top of the font's natural line height, which differs per font.
    static func lineSpacing(size: CGFloat, lineHeight: CGFloat) -> CGFloat {
        let font = uiFamily.flatMap { NSFont(name: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
        // The height AppKit text layout really gives a line (rounded up), not `ascender - descender + leading`.
        let natural = NSLayoutManager().defaultLineHeight(for: font)
        return max(0, lineHeight * size - natural)
    }

    /// Geist Mono: code, percentages, ports, IDs.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Geist Mono", size: size).weight(weight)
    }
}

enum FontRegistry {
    /// Registers the bundled variable fonts (Bricolage Grotesque, Geist, Geist Mono) for this process.
    static func registerAll() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}
