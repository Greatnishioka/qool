import AppKit

/// 意味を表示の属性へ写す。
///
/// **Domain は `NSFont` も `NSColor` も知りません。** 写すのはここだけの仕事です
/// （[#21](https://github.com/Greatnishioka/qool/issues/21)）。
nonisolated struct RichTextStyle {
    /// 本文の書体。見出しはここから倍率で作ります。
    let baseFont: NSFont
    /// 要素が持っている文字色。**`<span>` はこれを上書きします。**
    let baseColor: NSColor

    /// 見出しの大きさ。**深いほど本文へ近づきます。**
    private static let headingScales: [CGFloat] = [1.6, 1.35, 1.15]

    /// リストのぶら下げ幅（文字数ぶん）。
    private static let listIndentEms: CGFloat = 1.6

    init(baseFont: NSFont, baseColor: NSColor) {
        self.baseFont = baseFont
        self.baseColor = baseColor
    }

    func attributes(for kind: RichTextSpanKind, base: NSFont) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .strong:
            return [.font: Self.font(base, adding: .bold)]
        case .emphasis:
            return [.font: Self.font(base, adding: .italic)]
        case .strikethrough:
            return [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        case .inlineCode:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: base.pointSize * 0.92, weight: .regular),
                .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.12)
            ]
        case .link:
            // **`.link` は付けません。** 編集中にクリックが範囲選択ではなく
            // リンクを開く操作になり、書き換えられなくなります。
            return [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        case let .heading(level):
            let scale = Self.headingScales[min(max(level, 1), Self.headingScales.count) - 1]
            return [.font: Self.font(baseFont.withSize(baseFont.pointSize * scale), adding: .bold)]
        case .listItem:
            return [.paragraphStyle: Self.listParagraphStyle(base: baseFont)]
        case let .color(components):
            return [.foregroundColor: Self.color(components)]
        case .listMarker:
            // **隠しません。** 記号そのものが箇条書きの目印です。
            return [.foregroundColor: baseColor.withAlphaComponent(0.55)]
        case .syntax:
            return [:]
        }
    }

    /// 記法の文字を薄く見せる。**カーソルのあるブロックだけこちらです。**
    func visibleSyntaxAttributes() -> [NSAttributedString.Key: Any] {
        [.foregroundColor: baseColor.withAlphaComponent(0.3)]
    }

    /// 記法の文字を消す。
    ///
    /// **文字は消さず、幅を潰しています。** 生の Markdown を抱えたままにするのが
    /// この設計の土台なので、文字列からは取り除けません。色を透明にするだけだと
    /// `**` のぶんの隙間が残るため、大きさも潰します。
    ///
    /// **行の高さは変わりません。** 同じ行にある本文の書体が高さを決めるためです。
    func hiddenSyntaxAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: baseFont.withSize(0.01),
            .foregroundColor: NSColor.clear,
            .kern: 0
        ]
    }

    /// **`extension` へ出しません。** この型はメインアクターの外でも使うため、
    /// 別の宣言へ出すと既定でアクターに縛られ、呼べなくなります。
    private static func color(_ components: RGBAComponents) -> NSColor {
        NSColor(
            srgbRed: components.red,
            green: components.green,
            blue: components.blue,
            alpha: components.opacity
        )
    }

    private static func font(_ base: NSFont, adding trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(trait))

        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    private static func listParagraphStyle(base: NSFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let indent = base.pointSize * listIndentEms
        // **2 行目以降だけ下げます。** 1 行目は記号のぶん自然に下がります。
        style.headIndent = indent

        return style
    }
}
