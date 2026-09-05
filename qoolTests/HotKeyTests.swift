import Foundation
import Testing
@testable import qool

/// グローバルホットキー（第 3 段階 8）の検証。
@MainActor
struct HotKeyTests {
    /// 登録要求を記録するだけの偽物。**Carbon を呼ばずに、どのキーで登録し直したかを見ます。**
    private final class SpyGlobalHotKey: GlobalHotKeyProtocol {
        private(set) var registered: [HotKeyShortcut] = []
        private(set) var unregisterCount = 0
        var failsToRegister = false
        var onPress: (() -> Void)?

        func register(_ shortcut: HotKeyShortcut, onPress: @escaping () -> Void) throws {
            guard !failsToRegister else {
                throw HotKeyRegistrationFailure.rejectedBySystem(status: -9878)
            }

            registered.append(shortcut)
            self.onPress = onPress
        }

        func unregister() {
            unregisterCount += 1
        }
    }

    private final class InMemorySettings: AppSettingsProtocol {
        var hotKeyConfiguration: HotKeyConfiguration = .default
        var mainMemoID: Memo.ID?
    }

    private func makeCoordinator(
        settings: InMemorySettings = InMemorySettings(),
        hotKey: SpyGlobalHotKey = SpyGlobalHotKey()
    ) -> (HotKeyCoordinator, InMemorySettings, SpyGlobalHotKey) {
        let viewModel = AppRootViewModel.bootstrap(repository: InMemoryMemoRepositoryInfrastructure())

        return (
            HotKeyCoordinator(
                viewModel: viewModel,
                floatingMemos: FloatingMemoPresenter(viewModel: viewModel),
                settings: settings,
                globalHotKey: hotKey
            ),
            settings,
            hotKey
        )
    }

    // MARK: - 割り当て

    @Test func 初期値はプレフィックスにshiftとcontrolを要求する() {
        let prefix = HotKeyConfiguration.default.prefix

        #expect(prefix.keyCode == VirtualKey.q.rawValue)
        #expect(prefix.modifiers == [.shift, .control])
        // ⌃Q 単体はターミナルのフロー制御を奪うため、避けている。
        #expect(prefix.modifiers.contains(.shift))
    }

    @Test func 初期値のキーから操作を引ける() {
        let configuration = HotKeyConfiguration.default

        #expect(configuration.action(forKeyCode: VirtualKey.f.rawValue) == .toggleMainMemo)
        #expect(configuration.action(forKeyCode: VirtualKey.n.rawValue) == .createMemo)
        #expect(configuration.action(forKeyCode: VirtualKey.z.rawValue) == nil)
    }

    @Test func 表記は修飾キーの慣習順に並ぶ() {
        let shortcut = HotKeyShortcut(.q, modifiers: [.shift, .control, .command, .option])

        #expect(shortcut.displayName == "⌃⌥⇧⌘Q")
        #expect(HotKeyConfiguration.default.prefix.displayName == "⌃⇧Q")
    }

    // MARK: - 保存

    @Test func 設定は保存して読み戻せる() throws {
        let defaults = try #require(UserDefaults(suiteName: "qool.hotkey.\(UUID().uuidString)"))
        let settings = UserDefaultsAppSettingsInfrastructure(defaults: defaults)
        let changed = HotKeyConfiguration(
            prefix: HotKeyShortcut(.space, modifiers: [.option]),
            bindings: [HotKeyBinding(.m, .toggleMainMemo)]
        )

        settings.hotKeyConfiguration = changed

        #expect(UserDefaultsAppSettingsInfrastructure(defaults: defaults).hotKeyConfiguration == changed)
    }

    /// 設定が壊れていてもホットキーは効いてほしいので、初期値へ落とします。
    @Test func 読めない設定は初期値へ戻る() throws {
        let defaults = try #require(UserDefaults(suiteName: "qool.hotkey.\(UUID().uuidString)"))
        defaults.set(Data("これはJSONではない".utf8), forKey: "hotKeyConfiguration")

        #expect(UserDefaultsAppSettingsInfrastructure(defaults: defaults).hotKeyConfiguration == .default)
    }

    @Test func メインのメモは保存される() throws {
        let defaults = try #require(UserDefaults(suiteName: "qool.hotkey.\(UUID().uuidString)"))
        let settings = UserDefaultsAppSettingsInfrastructure(defaults: defaults)
        let memoID = UUID()

        settings.mainMemoID = memoID

        #expect(UserDefaultsAppSettingsInfrastructure(defaults: defaults).mainMemoID == memoID)
    }

    // MARK: - 登録

    @Test func 起動時に設定されたプレフィックスで登録する() {
        let (coordinator, _, hotKey) = makeCoordinator()

        coordinator.start()

        #expect(hotKey.registered == [HotKeyConfiguration.default.prefix])
        #expect(coordinator.registrationFailureMessage == nil)
    }

    @Test func 登録できなければ理由を伝える() {
        let hotKey = SpyGlobalHotKey()
        hotKey.failsToRegister = true
        let (coordinator, _, _) = makeCoordinator(hotKey: hotKey)

        coordinator.start()

        #expect(coordinator.registrationFailureMessage != nil)
    }

    @Test func プレフィックスを変えると登録し直す() {
        let (coordinator, settings, hotKey) = makeCoordinator()
        coordinator.start()

        coordinator.updatePrefix(keyCode: VirtualKey.space.rawValue, modifiers: [.option])

        #expect(hotKey.registered.count == 2)
        #expect(hotKey.registered.last == HotKeyShortcut(.space, modifiers: [.option]))
        #expect(settings.hotKeyConfiguration.prefix.keyCode == VirtualKey.space.rawValue)
    }

    // MARK: - 入力の検証

    /// 素のキーを OS 全体で奪うと、ほかのアプリでその文字が打てなくなります。
    @Test func 修飾キーのないプレフィックスは受け付けない() {
        let (coordinator, _, _) = makeCoordinator()

        #expect(coordinator.prefixRejection(keyCode: VirtualKey.q.rawValue, modifiers: []) != nil)
        #expect(coordinator.prefixRejection(keyCode: VirtualKey.q.rawValue, modifiers: [.control]) == nil)
    }

    @Test func escは2打目に割り当てられない() {
        let (coordinator, _, _) = makeCoordinator()

        #expect(coordinator.bindingRejection(keyCode: VirtualKey.escape.rawValue, for: .createMemo) != nil)
    }

    @Test func 他の操作と重なるキーは弾く() {
        let (coordinator, _, _) = makeCoordinator()

        // F は既定でメインのメモに割り当て済み。
        #expect(coordinator.bindingRejection(keyCode: VirtualKey.f.rawValue, for: .createMemo) != nil)
        // 自分自身への割り当て直しは重複ではありません。
        #expect(coordinator.bindingRejection(keyCode: VirtualKey.f.rawValue, for: .toggleMainMemo) == nil)
    }

    @Test func 割り当てを変えても並びは操作の定義順を保つ() {
        let (coordinator, _, _) = makeCoordinator()
        coordinator.start()

        coordinator.updateBinding(keyCode: VirtualKey.m.rawValue, for: .toggleMainMemo)

        #expect(coordinator.configuration.bindings.map(\.action) == HotKeyAction.allCases)
        #expect(coordinator.keyCode(for: .toggleMainMemo) == VirtualKey.m.rawValue)
        #expect(coordinator.keyCode(for: .createMemo) == VirtualKey.n.rawValue)
    }

    @Test func 初期値へ戻せる() {
        let (coordinator, settings, _) = makeCoordinator()
        coordinator.start()
        coordinator.updatePrefix(keyCode: VirtualKey.space.rawValue, modifiers: [.option])

        coordinator.resetConfiguration()

        #expect(coordinator.configuration == .default)
        #expect(settings.hotKeyConfiguration == .default)
    }

    // MARK: - メインのメモ

    @Test func メインのメモを指定すると保存される() async {
        let (coordinator, settings, _) = makeCoordinator()
        let memo = Memo(title: "メイン")

        coordinator.setMain(memo)

        #expect(coordinator.isMain(memo))
        #expect(settings.mainMemoID == memo.id)
    }
}
