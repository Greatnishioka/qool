import CoreGraphics

/// 輪郭候補がどの手段で作られたか。
///
/// `bias` はスコアに直接加算される優先度です（[抽出器の一覧](../../../docs/image-editing/02-contour-extractors.md)）。
/// Vision の被写体マスクが最優先、矩形補正は「他に何もなければ」という位置づけになっています。
///
/// **実装があるのは `rectangularGuide` / `subjectMask` / `grabCut` の 3 つです。**
/// 残りは順に移植します。
nonisolated enum ContourCandidateSource: String, CaseIterable, Identifiable, Hashable {
    case subjectMask
    case grabCut
    case preprocessedContour
    case backgroundDifference
    case lineColorContour
    case coloredRectangle
    case rectangularGuide
    case rawVisionContour

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .subjectMask:
            "被写体"
        case .grabCut:
            "領域分割"
        case .preprocessedContour:
            "前処理"
        case .backgroundDifference:
            "背景差分"
        case .lineColorContour:
            "線色"
        case .coloredRectangle:
            "色矩形"
        case .rectangularGuide:
            "矩形補正"
        case .rawVisionContour:
            "Vision"
        }
    }

    var helpText: String {
        switch self {
        case .subjectMask:
            "Vision の被写体マスクから作った候補です"
        case .grabCut:
            "なぞった範囲を種にして、色の分布から前景と背景を分けた候補です"
        case .preprocessedContour:
            "画像を二値化寄りに前処理してから輪郭検出した候補です"
        case .backgroundDifference:
            "ガイド周辺の背景色との差から作った候補です"
        case .lineColorContour:
            "なぞった線の近くから内側へ探した明るい有彩色の枠線候補です"
        case .coloredRectangle:
            "色付きの矩形領域として検出した候補です"
        case .rectangularGuide:
            "なぞった範囲を矩形として整えた候補です"
        case .rawVisionContour:
            "Vision の通常輪郭検出から作った候補です"
        }
    }

    var bias: CGFloat {
        switch self {
        case .subjectMask:
            0.55
        // **被写体マスクよりわずかに下です。** 検出が効く画像では Vision のほうが安定し、
        // 効かない画像（枠線のない被写体など）では Vision 自体が候補を出しません。
        case .grabCut:
            0.5
        case .preprocessedContour:
            0.24
        case .rawVisionContour:
            0.12
        case .backgroundDifference:
            0
        case .lineColorContour:
            0.08
        case .coloredRectangle:
            -0.04
        case .rectangularGuide:
            -0.18
        }
    }

    /// 表示前に `ContourSmoother.polished()` をかけるか。
    /// 矩形と色矩形はすでに直線的なので、かけると角が丸まります。
    var smoothsContour: Bool {
        switch self {
        case .coloredRectangle, .rectangularGuide:
            false
        case .subjectMask, .grabCut, .preprocessedContour, .backgroundDifference,
             .lineColorContour, .rawVisionContour:
            true
        }
    }
}
