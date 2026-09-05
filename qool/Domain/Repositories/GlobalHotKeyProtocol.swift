/// OS 全体で効くホットキーを 1 つ登録する。
///
/// **これが腐敗防止層です。** 実装は Carbon を使いますが、その事実はここから漏らしません。
/// ライブラリへ差し替えるときも、`HotKeyShortcut` を受けてコールバックを返す
/// この形さえ満たせば、Presentation から先は触らずに済みます。
@MainActor
protocol GlobalHotKeyProtocol: AnyObject {
    /// 登録できるのは 1 つだけです。**呼び直すと前の登録を置き換えます。**
    /// 押されたことだけを伝え、どのキーだったかは返しません（登録したものしか来ないため）。
    func register(_ shortcut: HotKeyShortcut, onPress: @escaping () -> Void) throws

    func unregister()
}
