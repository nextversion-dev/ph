import AppKit

/// Minimal Smalltalk syntax highlighter that converts a source string into
/// an NSAttributedString. Recognises:
///   - double-quoted comments  "like this"
///   - single-quoted strings   'like this'
///   - symbol literals         #foo or #'with spaces'
///   - reserved words          self super nil true false thisContext
///   - keyword selector parts  trailing colon like at:put:
///   - numeric literals
enum SmalltalkSyntaxHighlighter {

    private static let reservedWords: Set<String> = [
        "self", "super", "nil", "true", "false", "thisContext"
    ]

    static func highlight(_ source: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: source)
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: fullRange)
        attributed.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)

        let scalars = Array(source.unicodeScalars)
        var i = 0
        let n = scalars.count
        while i < n {
            let ch = scalars[i]
            if ch == "\"" {
                let start = i
                i += 1
                while i < n && scalars[i] != "\"" { i += 1 }
                if i < n { i += 1 } // include closing quote
                apply(to: attributed, scalarsRange: start..<i, color: commentColor, italic: true)
            } else if ch == "'" {
                let start = i
                i += 1
                while i < n {
                    if scalars[i] == "'" {
                        if i + 1 < n && scalars[i + 1] == "'" {
                            i += 2 // escaped quote
                        } else {
                            i += 1
                            break
                        }
                    } else {
                        i += 1
                    }
                }
                apply(to: attributed, scalarsRange: start..<i, color: stringColor)
            } else if ch == "#" {
                let start = i
                i += 1
                if i < n && scalars[i] == "'" {
                    i += 1
                    while i < n && scalars[i] != "'" { i += 1 }
                    if i < n { i += 1 }
                } else {
                    while i < n && isIdentifierChar(scalars[i]) { i += 1 }
                }
                apply(to: attributed, scalarsRange: start..<i, color: symbolColor)
            } else if isIdentifierStart(ch) {
                let start = i
                while i < n && isIdentifierChar(scalars[i]) { i += 1 }
                let word = String(String.UnicodeScalarView(scalars[start..<i]))
                if reservedWords.contains(word) {
                    apply(to: attributed, scalarsRange: start..<i, color: reservedColor, bold: true)
                } else if i < n && scalars[i] == ":" {
                    i += 1
                    apply(to: attributed, scalarsRange: start..<i, color: keywordPartColor)
                }
            } else if isDigit(ch) {
                let start = i
                while i < n && (isDigit(scalars[i]) || scalars[i] == "." || scalars[i] == "r" || scalars[i] == "e" || scalars[i] == "-") {
                    i += 1
                }
                apply(to: attributed, scalarsRange: start..<i, color: numberColor)
            } else {
                i += 1
            }
        }

        return attributed
    }

    // MARK: helpers

    private static func apply(
        to attributed: NSMutableAttributedString,
        scalarsRange: Range<Int>,
        color: NSColor,
        bold: Bool = false,
        italic: Bool = false
    ) {
        let nsRange = NSRange(location: scalarsRange.lowerBound, length: scalarsRange.count)
        attributed.addAttribute(.foregroundColor, value: color, range: nsRange)
        if bold || italic {
            var traits: NSFontTraitMask = []
            if bold { traits.insert(.boldFontMask) }
            if italic { traits.insert(.italicFontMask) }
            let base = NSFont.monospacedSystemFont(ofSize: 13, weight: bold ? .semibold : .regular)
            let font = NSFontManager.shared.font(
                withFamily: base.familyName ?? "Menlo",
                traits: traits,
                weight: bold ? 8 : 5,
                size: 13
            ) ?? base
            attributed.addAttribute(.font, value: font, range: nsRange)
        }
    }

    private static func isIdentifierStart(_ c: Unicode.Scalar) -> Bool {
        return (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || c == "_"
    }

    private static func isIdentifierChar(_ c: Unicode.Scalar) -> Bool {
        return isIdentifierStart(c) || isDigit(c)
    }

    private static func isDigit(_ c: Unicode.Scalar) -> Bool {
        return c >= "0" && c <= "9"
    }

    // MARK: colors (dark-mode aware via dynamic colors)

    private static var commentColor: NSColor   { NSColor.systemGreen }
    private static var stringColor: NSColor    { NSColor.systemRed }
    private static var symbolColor: NSColor    { NSColor.systemPurple }
    private static var reservedColor: NSColor  { NSColor.systemBlue }
    private static var keywordPartColor: NSColor { NSColor.systemTeal }
    private static var numberColor: NSColor    { NSColor.systemOrange }
}
