import Foundation

/// 道具としての見せ方。**Domain には表示のことを書きません。**
extension InlineMarkdownStyle {
    var displayName: String {
        switch self {
        case .strong: return "太字"
        case .emphasis: return "斜体"
        case .strikethrough: return "打ち消し"
        case .inlineCode: return "コード"
        }
    }

    var systemImage: String {
        switch self {
        case .strong: return "bold"
        case .emphasis: return "italic"
        case .strikethrough: return "strikethrough"
        case .inlineCode: return "chevron.left.forwardslash.chevron.right"
        }
    }
}
