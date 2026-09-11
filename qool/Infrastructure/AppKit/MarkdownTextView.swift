import AppKit

/// Markdown を生のまま抱えるテキストビュー。
///
/// **`string` は常に保存する Markdown と一字一句同じです。** 記法の文字は消さず、
/// 見せ方だけを属性で変えます（[#21](https://github.com/Greatnishioka/qool/issues/21)）。
/// 記法を除いた文字列を編集して後から Markdown へ戻す作りは採りません。
/// `**` と `__`、エスケープ、書きかけの記法が多対多になり、往復が安定しないためです。
///
/// この不変条件のおかげで、**`selectedRange()` がそのまま Markdown 上の位置**になります。
final class MarkdownTextView: NSTextView {
    /// Esc で編集を終える。**閉じる手段が要ります。**
    /// クリックを外へ出すだけだと、キャンバスの端にある要素から抜けられません。
    var onEndEditing: (() -> Void)?
    /// 変換の状態が変わった。**変換中は外へ文字を出せない**ので、境目を知る必要があります。
    var onCompositionChange: (() -> Void)?

    /// **文字の入れ物を自分で持ちます。** `NSTextLayoutManager.textContentManager` は
    /// 弱い参照なので、組み立てた場所を出た時点で入れ物が消え、
    /// **警告も出さずに TextKit 1 へ落ちます**（段階 0 で踏みました）。
    private var contentStorage: NSTextContentStorage?

    /// TextKit 2 で組み立てる。
    ///
    /// **`NSTextView(usingTextLayoutManager:)` は継いだ型では使えません。**
    /// 継ぐ場合は `init(frame:textContainer:)` しか通らないので、入れ物を自分で組みます。
    static func make() -> MarkdownTextView {
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.textContainer = container

        let contentStorage = NSTextContentStorage()
        contentStorage.addTextLayoutManager(layoutManager)

        let textView = MarkdownTextView(frame: .zero, textContainer: container)
        textView.contentStorage = contentStorage
        textView.allowsUndo = true
        // **四角い背景を描きません。** 貼ったメモは輪郭でしか見えていないので、
        // ここで塗ると形が壊れます。塗りは呼び出し側が要素の色で敷きます。
        textView.drawsBackground = false
        textView.textContainerInset = CGSize(width: 6, height: 6)
        // **自動置換をすべて切ります。** 引用符やダッシュを勝手に変えられると、
        // Markdown の記法そのものが書き換わります。
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        return textView
    }

    /// 変換中か。**真の間は文字を外へ出さず、属性も貼り直しません。**
    var isComposing: Bool { hasMarkedText() }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onCompositionChange?()
    }

    override func unmarkText() {
        super.unmarkText()
        onCompositionChange?()
    }

    override func cancelOperation(_ sender: Any?) {
        // **変換中の Esc は変換の取り消しです。** ここで編集を抜けると、
        // 変換をやめたいだけの操作で編集モードごと閉じてしまいます。
        guard !isComposing else {
            super.cancelOperation(sender)
            return
        }

        onEndEditing?()
    }
}
