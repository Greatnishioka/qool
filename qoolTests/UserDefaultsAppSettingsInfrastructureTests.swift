import Foundation
import Testing
@testable import qool

/// 設定の保存と読み戻しの検証。
struct UserDefaultsAppSettingsInfrastructureTests {
    @MainActor
    @Test func 手直しの上限は保存して読み戻せる() throws {
        let defaults = try #require(UserDefaults(suiteName: "qool.history.\(UUID().uuidString)"))
        let settings = UserDefaultsAppSettingsInfrastructure(defaults: defaults)

        #expect(settings.editHistoryLimit == CutoutMaskEditHistory.defaultLimit)

        settings.editHistoryLimit = 320

        #expect(UserDefaultsAppSettingsInfrastructure(defaults: defaults).editHistoryLimit == 320)
    }

    /// **未設定と 0 を区別できているかの確認。** `UserDefaults.integer` は
    /// 未設定でも 0 を返すので、そのままだと既定値へ落とせません。
    @MainActor
    @Test func 範囲外の上限は丸めて読む() throws {
        let defaults = try #require(UserDefaults(suiteName: "qool.history.\(UUID().uuidString)"))
        defaults.set(9999, forKey: "editHistoryLimit")

        let limit = UserDefaultsAppSettingsInfrastructure(defaults: defaults).editHistoryLimit

        #expect(limit == CutoutMaskEditHistory.limitRange.upperBound)
    }
}
