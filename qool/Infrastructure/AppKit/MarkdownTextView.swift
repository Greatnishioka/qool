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

    /// 幅を潰して見えなくした記法の範囲。
    ///
    /// **キャレットと選択をここへ入れないために持ちます。** 文字としては残っているので、
    /// 放っておくと見えないタグが選択に入り、書式を付けたときに本文が壊れます。
    private(set) var hiddenSyntaxRanges: [NSRange] = []

    /// その範囲を数えたときの本文。
    ///
    /// **本文が変われば位置はずれます。** 文字を消した直後に古い位置で守ると、
    /// 関係のない場所へキャレットが飛びます。一致するときだけ使います。
    private(set) var hiddenSyntaxSource = ""

    func setHiddenSyntaxRanges(_ ranges: [NSRange], for source: String) {
        hiddenSyntaxRanges = ranges
        hiddenSyntaxSource = source
    }

    /// **文字の入れ物を自分で持ちます。** `NSTextLayoutManager.textContentManager` は
    /// 弱い参照なので、組み立てた場所を出た時点で入れ物が消え、
    /// **警告も出さずに TextKit 1 へ落ちます**（段階 0 で踏みました）。
    private var contentStorage: NSTextContentStorage?
    private let selectionGuard = MarkdownSelectionGuard()

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

    /// 選択の始まりがある行の矩形。**道具を浮かせる場所**に使います。
    ///
    /// **`textLayoutFragment` は使えません。** TextKit 2 の layout fragment は
    /// 行ではなく**段落 1 つ分**なので、折り返しの多い段落では
    /// **選んだ行ではなく段落の先頭の矩形**が返ります。道具が本文のはるか上に出ます
    /// （[#21](https://github.com/Greatnishioka/qool/issues/21) の段階 5 で踏みました）。
    ///
    /// **最初の断片だけ取ります。** 複数行を選んだときは、選び始めた行の上に出します。
    func selectionLineRect() -> CGRect? {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager else {
            return nil
        }

        let selected = selectedRange()
        let documentStart = contentManager.documentRange.location

        guard let start = contentManager.location(documentStart, offsetBy: selected.location),
              let end = contentManager.location(documentStart, offsetBy: selected.location + selected.length),
              let range = NSTextRange(location: start, end: end) else {
            return nil
        }

        var firstSegment: CGRect?

        layoutManager.enumerateTextSegments(in: range, type: .standard) { _, frame, _, _ in
            firstSegment = frame

            return false
        }

        guard let firstSegment else {
            return nil
        }

        return firstSegment.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    // MARK: - 削除

    /// **記法は丸ごと消します。** `**太字**` の後ろで 1 文字消すと `**太字*` になり、
    /// 太字でもなくなったうえに記号だけが残ります。
    override func deleteBackward(_ sender: Any?) {
        let selected = selectedRange()
        let target = selected.length > 0
            ? selected
            : NSRange(location: max(0, selected.location - 1), length: min(1, selected.location))

        guard !deleteMergingSyntax(target) else {
            return
        }

        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        let selected = selectedRange()
        let target = selected.length > 0
            ? selected
            : NSRange(location: selected.location, length: min(1, string.utf16.count - selected.location))

        guard !deleteMergingSyntax(target) else {
            return
        }

        super.deleteForward(sender)
    }

    /// 記法にかかっていれば、その記法ごと消す。消したら `true`。
    private func deleteMergingSyntax(_ target: NSRange) -> Bool {
        guard hiddenSyntaxSource == string else {
            return false
        }

        let merged = selectionGuard.deletion(target, avoiding: hiddenSyntaxRanges)

        guard merged != target, merged.length > 0, shouldChangeText(in: merged, replacementString: "") else {
            return false
        }

        textStorage?.replaceCharacters(in: merged, with: "")
        didChangeText()

        return true
    }

    /// **入力コンテキストを自分で起動します。**
    ///
    /// デスクトップに貼ったメモの窓は枠なしで、中身は `NSHostingView` の下にあります。
    /// この形だと、ファーストレスポンダになっても **AppKit が入力コンテキストを
    /// 起動しないことがあります。** そうなると `NSTextInputContext.current` が `nil` のままで、
    /// **入力メソッドが渡す相手を失います。**
    ///
    /// 症状は「英字は打てるが、かなが 1 文字も入らない」です。英字は入力メソッドを
    /// 通らず `insertText` へ直接来るため、違いに気づきにくくなります。
    /// 変換候補の窓だけが画面の隅に出たままになります（実機の記録で確認しました）。
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()

        if result {
            inputContext?.activate()
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()

        if result {
            inputContext?.deactivate()
        }
        return result
    }

    /// 高さが変わったら、キャレットを見えるところへ送り直す。
    ///
    /// **TextKit 2 は高さを見積もりで返します。** 組み終わってから本当の値に直すので、
    /// 打った直後に `NSTextView` が合わせた位置は、**あとから来る高さの修正で崩れます。**
    /// 長い本文を打っていると、打ち終わりに少し上へ巻き戻る形で出ます
    /// （実機の記録で、こちらのコードを通らない場所で高さが 53pt 縮むのを確認しました）。
    ///
    /// **書き換え中だけ追いかけます。** 表示だけのときに動かすと、読んでいる場所が飛びます。
    /// **変換中も動かしません。** 候補を選んでいる最中に画面が動くと選びにくくなります。
    override func setFrameSize(_ newSize: NSSize) {
        let didChangeHeight = newSize.height != frame.height
        super.setFrameSize(newSize)

        guard didChangeHeight, isEditable, !isComposing else {
            return
        }

        scrollRangeToVisible(selectedRange())
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
