import Foundation

/// 設定を `UserDefaults` に置く。
///
/// **メモと同じファイル方式にはしていません。** 単一で小さく、書き込みの失敗を
/// 画面へ伝える必要もないため、まとめ書きや再試行の仕組みが要りません。
@MainActor
final class UserDefaultsAppSettingsInfrastructure: AppSettingsProtocol {
    private enum StorageKey {
        static let hotKeyConfiguration = "hotKeyConfiguration"
        static let mainMemoID = "mainMemoID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 読めなければ初期値へ戻します。**設定が壊れていてもホットキーは効く**ほうが被害が小さいためです。
    var hotKeyConfiguration: HotKeyConfiguration {
        get {
            guard let data = defaults.data(forKey: StorageKey.hotKeyConfiguration),
                  let configuration = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data) else {
                return .default
            }

            return configuration
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                return
            }

            defaults.set(data, forKey: StorageKey.hotKeyConfiguration)
        }
    }

    var mainMemoID: Memo.ID? {
        get { defaults.string(forKey: StorageKey.mainMemoID).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: StorageKey.mainMemoID) }
    }
}
