import SwiftUI
import AppKit

/// Converts between the plain-text markdown-ish convention notes are stored
/// in (so they sync as plain text to Google Tasks/Calendar) and the rich
/// NSAttributedString the editor actually displays/edits.
///
/// Supported syntax: **bold**, *italic*, _underline_, [text](url) links,
/// and lines starting "- " (bullet) or "1. " (numbered). Combining more
/// than one style on the exact same span of text isn't guaranteed to
/// round-trip perfectly through serialization (whichever style is highest
/// priority — link, then bold, then italic, then underline — wins on
/// save); each style on its own always round-trips correctly.
enum RichTextFormat {
    static let bulletMarker = "•\u{00A0}"

    private static let baseFont = NSFont.systemFont(ofSize: 12)

    // Explicit color: without it, text drawn from an attributed string
    // falls back to black regardless of the window's light/dark appearance.
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.textColor]
    }

    private static func attributes(font: NSFont, underline: Bool = false) -> [NSAttributedString.Key: Any] {
        var attrs = baseAttributes
        attrs[.font] = font
        if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attrs
    }

    private static let inlineRegex = try! NSRegularExpression(
        pattern: #"\[([^\]]+)\]\(([^)]+)\)|\*\*(.+?)\*\*|\*(.+?)\*|_(.+?)_"#
    )

    static let numberedLinePrefixRegex = try! NSRegularExpression(pattern: "^(\\d+)\\.\u{00A0}")
    private static let numberedTypedPrefixRegex = try! NSRegularExpression(pattern: "^(\\d+)\\.$")

    static func attributedString(from markdown: String) -> NSAttributedString {
        guard !markdown.isEmpty else { return NSAttributedString(string: "", attributes: baseAttributes) }

        let lines = markdown.components(separatedBy: "\n")
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
            if line.hasPrefix("- ") {
                let content = String(line.dropFirst(2))
                let marker = NSAttributedString(string: bulletMarker, attributes: baseAttributes)
                let para = NSMutableAttributedString(attributedString: marker)
                para.append(parseInline(content))
                applyHangingIndent(to: para)
                result.append(para)
            } else if let match = numberedTypedLineMatch(line) {
                let number = match.number
                let content = match.remainder
                let marker = NSAttributedString(string: "\(number).\u{00A0}", attributes: baseAttributes)
                let para = NSMutableAttributedString(attributedString: marker)
                para.append(parseInline(content))
                applyHangingIndent(to: para)
                result.append(para)
            } else {
                result.append(parseInline(line))
            }
        }
        return result
    }

    private static func numberedTypedLineMatch(_ line: String) -> (number: Int, remainder: String)? {
        let ns = line as NSString
        guard let match = numberedLinePrefixRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let numberString = ns.substring(with: match.range(at: 1))
        guard let number = Int(numberString) else { return nil }
        let remainder = ns.substring(from: match.range(at: 0).length)
        return (number, remainder)
    }

    private static func applyHangingIndent(to attributed: NSMutableAttributedString) {
        let style = NSMutableParagraphStyle()
        style.headIndent = 18
        style.firstLineHeadIndent = 0
        attributed.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: attributed.length))
    }

    private static func parseInline(_ text: String) -> NSAttributedString {
        guard !text.isEmpty else { return NSAttributedString(string: "", attributes: baseAttributes) }
        let ns = text as NSString
        let result = NSMutableAttributedString()
        var lastIndex = 0

        let matches = inlineRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            let fullRange = match.range
            if fullRange.location > lastIndex {
                let plain = ns.substring(with: NSRange(location: lastIndex, length: fullRange.location - lastIndex))
                result.append(NSAttributedString(string: plain, attributes: baseAttributes))
            }

            if match.range(at: 1).location != NSNotFound {
                // Link: [text](url)
                let linkText = ns.substring(with: match.range(at: 1))
                let urlString = ns.substring(with: match.range(at: 2))
                var attrs: [NSAttributedString.Key: Any] = baseAttributes
                if let url = URL(string: urlString) {
                    attrs[.link] = url
                    attrs[.foregroundColor] = NSColor.linkColor
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                result.append(NSAttributedString(string: linkText, attributes: attrs))
            } else if match.range(at: 3).location != NSNotFound {
                // Bold
                let boldText = ns.substring(with: match.range(at: 3))
                result.append(NSAttributedString(string: boldText, attributes: attributes(font: boldFont())))
            } else if match.range(at: 4).location != NSNotFound {
                // Italic
                let italicText = ns.substring(with: match.range(at: 4))
                result.append(NSAttributedString(string: italicText, attributes: attributes(font: italicFont())))
            } else if match.range(at: 5).location != NSNotFound {
                // Underline
                let underlineText = ns.substring(with: match.range(at: 5))
                result.append(NSAttributedString(string: underlineText, attributes: attributes(font: baseFont, underline: true)))
            }
            lastIndex = fullRange.location + fullRange.length
        }
        if lastIndex < ns.length {
            let plain = ns.substring(from: lastIndex)
            result.append(NSAttributedString(string: plain, attributes: baseAttributes))
        }
        return result
    }

    private static func boldFont() -> NSFont {
        NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
    }

    private static func italicFont() -> NSFont {
        NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
    }

    static func markdown(from attributed: NSAttributedString) -> String {
        let fullString = attributed.string as NSString
        guard fullString.length > 0 else { return "" }

        var lines: [String] = []
        fullString.enumerateSubstrings(in: NSRange(location: 0, length: fullString.length), options: .byParagraphs) { _, paragraphRange, _, _ in
            lines.append(serializeParagraph(attributed, range: paragraphRange))
        }
        return lines.joined(separator: "\n")
    }

    private static func serializeParagraph(_ attributed: NSAttributedString, range: NSRange) -> String {
        let paragraphText = attributed.attributedSubstring(from: range).string as NSString
        var prefix = ""
        var contentRange = range

        if paragraphText.hasPrefix(bulletMarker) {
            prefix = "- "
            let markerLength = (bulletMarker as NSString).length
            contentRange = NSRange(location: range.location + markerLength, length: range.length - markerLength)
        } else if let match = numberedLinePrefixRegex.firstMatch(in: paragraphText as String, range: NSRange(location: 0, length: paragraphText.length)) {
            let numberString = paragraphText.substring(with: match.range(at: 1))
            prefix = "\(numberString). "
            let markerLength = match.range(at: 0).length
            contentRange = NSRange(location: range.location + markerLength, length: range.length - markerLength)
        }

        guard contentRange.length > 0 else { return prefix }
        var body = ""
        attributed.enumerateAttributes(in: contentRange, options: []) { attrs, runRange, _ in
            let runText = (attributed.string as NSString).substring(with: runRange)
            body += serializeRun(runText, attrs: attrs)
        }
        return prefix + body
    }

    private static func serializeRun(_ text: String, attrs: [NSAttributedString.Key: Any]) -> String {
        guard !text.isEmpty else { return text }
        var result = text

        if let url = attrs[.link] as? URL {
            return "[\(result)](\(url.absoluteString))"
        } else if let urlString = attrs[.link] as? String {
            return "[\(result)](\(urlString))"
        }

        if let font = attrs[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.bold) {
                result = "**\(result)**"
                return result
            } else if traits.contains(.italic) {
                result = "*\(result)*"
                return result
            }
        }

        if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
            result = "_\(result)_"
        }

        return result
    }
}

/// A custom NSTextView that continues bullet/numbered lists on Return,
/// auto-converts "- " / "1. " typed at the start of a line into a real
/// list marker, and treats Shift+Return as a plain line break that never
/// triggers list behavior.
final class ListAwareTextView: NSTextView {
    private static let numberedTypedPrefixRegex = try! NSRegularExpression(pattern: "^(\\d+)\\.$")

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return
            if event.modifierFlags.contains(.shift) {
                insertText("\n", replacementRange: selectedRange())
                return
            }
        }
        if event.modifierFlags.contains(.command), let chars = event.charactersIgnoringModifiers {
            switch chars.lowercased() {
            case "b": toggleBold(); return
            case "i": toggleItalic(); return
            case "u": toggleUnderlineStyle(); return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    func toggleBold() { toggleTrait(.bold) }
    func toggleItalic() { toggleTrait(.italic) }

    private func toggleTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        let fontManager = NSFontManager.shared
        let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask

        if range.length > 0 {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 12)
                let hasTrait = font.fontDescriptor.symbolicTraits.contains(trait)
                let newFont = hasTrait ? fontManager.convert(font, toNotHaveTrait: mask) : fontManager.convert(font, toHaveTrait: mask)
                storage.addAttribute(.font, value: newFont, range: subrange)
            }
            storage.endEditing()
            didChangeText()
        } else {
            let font = (typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
            let hasTrait = font.fontDescriptor.symbolicTraits.contains(trait)
            typingAttributes[.font] = hasTrait ? fontManager.convert(font, toNotHaveTrait: mask) : fontManager.convert(font, toHaveTrait: mask)
        }
    }

    func toggleUnderlineStyle() {
        let range = selectedRange()
        if range.length > 0, let storage = textStorage {
            var isUnderlined = false
            storage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, stop in
                if let v = value as? Int, v != 0 { isUnderlined = true }
                stop.pointee = true
            }
            storage.addAttribute(.underlineStyle, value: isUnderlined ? 0 : NSUnderlineStyle.single.rawValue, range: range)
            didChangeText()
        } else {
            let current = typingAttributes[.underlineStyle] as? Int ?? 0
            typingAttributes[.underlineStyle] = current != 0 ? 0 : NSUnderlineStyle.single.rawValue
        }
    }

    override func insertNewline(_ sender: Any?) {
        if handleListContinuation() { return }
        super.insertNewline(sender)
    }

    override func didChangeText() {
        super.didChangeText()
        maybeAutoConvertListPrefix()
    }

    func applyLink(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = resolvedURL(from: trimmed), let storage = textStorage else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }
        storage.addAttribute(.link, value: url, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        didChangeText()
    }

    private func resolvedURL(from string: String) -> URL? {
        guard !string.isEmpty else { return nil }
        if string.contains("://") { return URL(string: string) }
        return URL(string: "https://\(string)")
    }

    private func handleListContinuation() -> Bool {
        guard let storage = textStorage else { return false }
        let ns = string as NSString
        let cursor = selectedRange().location
        let paraRange = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
        let paraText = ns.substring(with: paraRange)

        if paraText.hasPrefix(RichTextFormat.bulletMarker) {
            let content = String(paraText.dropFirst(RichTextFormat.bulletMarker.count))
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                storage.replaceCharacters(in: paraRange, with: "")
                setSelectedRange(NSRange(location: paraRange.location, length: 0))
            } else {
                insertText("\n" + RichTextFormat.bulletMarker, replacementRange: selectedRange())
                applyHangingIndentToCurrentParagraph()
            }
            return true
        }

        if let match = RichTextFormat.numberedLinePrefixRegex.firstMatch(in: paraText, range: NSRange(location: 0, length: (paraText as NSString).length)) {
            let markerLength = match.range(at: 0).length
            let content = (paraText as NSString).substring(from: markerLength)
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                storage.replaceCharacters(in: paraRange, with: "")
                setSelectedRange(NSRange(location: paraRange.location, length: 0))
            } else {
                let numberString = (paraText as NSString).substring(with: match.range(at: 1))
                let number = Int(numberString) ?? 1
                insertText("\n\(number + 1).\u{00A0}", replacementRange: selectedRange())
                applyHangingIndentToCurrentParagraph()
            }
            return true
        }

        return false
    }

    private func maybeAutoConvertListPrefix() {
        guard let storage = textStorage else { return }
        let ns = string as NSString
        let cursor = selectedRange().location
        guard cursor <= ns.length else { return }
        let paraRange = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
        guard cursor >= paraRange.location else { return }
        let lineSoFar = ns.substring(with: NSRange(location: paraRange.location, length: cursor - paraRange.location))

        if lineSoFar == "- " {
            let replaceRange = NSRange(location: paraRange.location, length: (lineSoFar as NSString).length)
            storage.replaceCharacters(in: replaceRange, with: RichTextFormat.bulletMarker)
            setSelectedRange(NSRange(location: paraRange.location + (RichTextFormat.bulletMarker as NSString).length, length: 0))
            applyHangingIndentToCurrentParagraph()
        } else if let match = Self.numberedTypedPrefixRegex.firstMatch(in: lineSoFar, range: NSRange(location: 0, length: (lineSoFar as NSString).length)) {
            _ = match
            let numberPart = String(lineSoFar.dropLast()) // drop trailing space check below
            guard lineSoFar.hasSuffix(" ") else { return }
            let digits = numberPart.dropLast() // drop trailing "."
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return }
            let marker = "\(digits).\u{00A0}"
            let replaceRange = NSRange(location: paraRange.location, length: (lineSoFar as NSString).length)
            storage.replaceCharacters(in: replaceRange, with: marker)
            setSelectedRange(NSRange(location: paraRange.location + (marker as NSString).length, length: 0))
            applyHangingIndentToCurrentParagraph()
        }
    }

    private func applyHangingIndentToCurrentParagraph() {
        guard let storage = textStorage else { return }
        let ns = string as NSString
        let cursor = min(selectedRange().location, ns.length)
        let paraRange = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
        let style = NSMutableParagraphStyle()
        style.headIndent = 18
        style.firstLineHeadIndent = 0
        storage.addAttribute(.paragraphStyle, value: style, range: paraRange)
    }
}

/// A small rich-text note editor: a formatting toolbar (bold, italic,
/// underline, link) above a wrapping, multi-line text view. Backed by
/// NSTextView since SwiftUI's TextEditor can't do rich text or custom
/// Return-key handling.
struct RichNoteEditor: NSViewRepresentable {
    @Binding var text: String
    var onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 2

        let textView = ListAwareTextView()
        context.coordinator.textView = textView

        func makeButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(), target: context.coordinator, action: action)
            button.isBordered = false
            button.contentTintColor = .secondaryLabelColor
            button.toolTip = tooltip
            button.controlSize = .small
            return button
        }

        toolbar.addArrangedSubview(makeButton(symbol: "bold", tooltip: "Bold (Cmd-B)", action: #selector(Coordinator.toggleBold)))
        toolbar.addArrangedSubview(makeButton(symbol: "italic", tooltip: "Italic (Cmd-I)", action: #selector(Coordinator.toggleItalic)))
        toolbar.addArrangedSubview(makeButton(symbol: "underline", tooltip: "Underline (Cmd-U)", action: #selector(Coordinator.toggleUnderline)))
        toolbar.addArrangedSubview(makeButton(symbol: "link", tooltip: "Add Link", action: #selector(Coordinator.insertLink)))

        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close") ?? NSImage(), target: context.coordinator, action: #selector(Coordinator.close))
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "Close"
        closeButton.controlSize = .small

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let toolbarRow = NSStackView(views: [toolbar, spacer, closeButton])
        toolbarRow.orientation = .horizontal
        toolbarRow.distribution = .fill

        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isAutomaticDataDetectionEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.textColor = .textColor
        textView.typingAttributes = RichTextFormat.baseAttributes
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textStorage?.setAttributedString(RichTextFormat.attributedString(from: text))
        // Transparent, not a hardcoded color — so it always shows exactly
        // whatever background the row itself has, with no risk of drifting
        // out of sync with it.
        textView.drawsBackground = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 90).isActive = true

        container.addArrangedSubview(toolbarRow)
        container.addArrangedSubview(scrollView)
        toolbarRow.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        scrollView.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        context.coordinator.onTextChange = { newText in
            if text != newText { text = newText }
        }
        context.coordinator.onClose = onClose

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let currentMarkdown = RichTextFormat.markdown(from: textView.attributedString())
        if currentMarkdown != text {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(RichTextFormat.attributedString(from: text))
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(selectedRange.location, length), length: 0))
        }
        context.coordinator.onClose = onClose
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: ListAwareTextView?
        var onTextChange: ((String) -> Void)?
        var onClose: (() -> Void)?

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            onTextChange?(RichTextFormat.markdown(from: textView.attributedString()))
        }

        @objc func toggleBold() {
            textView?.toggleBold()
            if let textView { onTextChange?(RichTextFormat.markdown(from: textView.attributedString())) }
        }
        @objc func toggleItalic() {
            textView?.toggleItalic()
            if let textView { onTextChange?(RichTextFormat.markdown(from: textView.attributedString())) }
        }
        @objc func toggleUnderline() {
            textView?.toggleUnderlineStyle()
            if let textView { onTextChange?(RichTextFormat.markdown(from: textView.attributedString())) }
        }
        @objc func close() { onClose?() }

        @objc func insertLink() {
            guard let textView, textView.selectedRange().length > 0 else { return }
            let alert = NSAlert()
            alert.messageText = "Add Link"
            alert.informativeText = "Enter the URL for the selected text."
            alert.addButton(withTitle: "Add")
            alert.addButton(withTitle: "Cancel")
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            field.placeholderString = "https://example.com"
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            if alert.runModal() == .alertFirstButtonReturn {
                textView.applyLink(urlString: field.stringValue)
                onTextChange?(RichTextFormat.markdown(from: textView.attributedString()))
            }
        }
    }
}
