nonisolated extension VirtualKey {
    var symbol: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .c: return "C"
        case .d: return "D"
        case .e: return "E"
        case .f: return "F"
        case .g: return "G"
        case .h: return "H"
        case .i: return "I"
        case .j: return "J"
        case .k: return "K"
        case .l: return "L"
        case .m: return "M"
        case .n: return "N"
        case .o: return "O"
        case .p: return "P"
        case .q: return "Q"
        case .r: return "R"
        case .s: return "S"
        case .t: return "T"
        case .u: return "U"
        case .v: return "V"
        case .w: return "W"
        case .x: return "X"
        case .y: return "Y"
        case .z: return "Z"
        case .zero: return "0"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .returnKey: return "↩"
        case .tab: return "⇥"
        case .space: return "空白"
        case .delete: return "⌫"
        case .escape: return "esc"
        }
    }

    /// 対応表にないキーは、キーコードをそのまま出します。**空欄にすると設定できたのか分かりません。**
    static func symbol(forKeyCode keyCode: UInt16) -> String {
        VirtualKey(rawValue: keyCode)?.symbol ?? "#\(keyCode)"
    }
}
