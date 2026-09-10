import CoreGraphics

/// 切り抜きのマスクに、なぞった範囲を足す / 引く。
///
/// **多角形のブーリアン演算をやめました。** マスクどうしの比較で済むので、
/// 極小の欠片を捨てる後始末が要らず、**縁の柔らかさもそのまま残ります**
/// （[設計](https://github.com/Greatnishioka/qool/issues/12)）。
nonisolated struct EditCutoutMaskUseCase {
    init() {}

    /// - Parameters:
    ///   - mask: 今のマスク。
    ///   - stamp: なぞりから作ったマスク。**同じ格子に載っている前提**です。
    ///   - mode: 足すか引くか。
    /// - Returns: 合成後のマスク。格子が違えば元のまま返します。
    func callAsFunction(
        _ mask: CutoutMask,
        combining stamp: CutoutMask,
        mode: ContourEditMode
    ) -> CutoutMask {
        guard mask.width == stamp.width, mask.height == stamp.height else {
            return mask
        }

        // 複製を書き換えます。読み出しも同じ配列で足りるので、入れ子は 2 段で済みます。
        var coverage = mask.coverage

        coverage.withUnsafeMutableBufferPointer { destination in
            stamp.coverage.withUnsafeBufferPointer { added in
                for index in 0..<destination.count {
                    destination[index] = combine(destination[index], added[index], mode: mode)
                }
            }
        }

        return CutoutMask(
            extent: mask.extent,
            width: mask.width,
            height: mask.height,
            coverage: coverage
        ) ?? mask
    }

    /// 足すときは濃いほうを採り、引くときは残る割合を掛けます。
    ///
    /// **引き算に掛け算を使うのは、柔らかい縁を保つため**です。単純に引くと、
    /// 半分だけ覆われていた画素が一気に 0 まで落ちて縁が硬くなります。
    private func combine(_ current: UInt8, _ added: UInt8, mode: ContourEditMode) -> UInt8 {
        switch mode {
        case .add:
            return max(current, added)
        case .subtract:
            return UInt8(Int(current) * (255 - Int(added)) / 255)
        }
    }
}
