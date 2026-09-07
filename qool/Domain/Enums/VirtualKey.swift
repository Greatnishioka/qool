/// キーの位置を表す仮想キーコード。
///
/// **文字ではなく位置なので、キーボード配列を変えても同じ値です。**
/// ここにないキーも `HotKeyShortcut.keyCode` には入れられます。この列挙は
/// 既定値の記述と画面表示のための対応表で、扱えるキーを縛るものではありません。
nonisolated enum VirtualKey: UInt16, CaseIterable, Sendable {
    case a = 0x00
    case s = 0x01
    case d = 0x02
    case f = 0x03
    case h = 0x04
    case g = 0x05
    case z = 0x06
    case x = 0x07
    case c = 0x08
    case v = 0x09
    case b = 0x0B
    case q = 0x0C
    case w = 0x0D
    case e = 0x0E
    case r = 0x0F
    case y = 0x10
    case t = 0x11
    case one = 0x12
    case two = 0x13
    case three = 0x14
    case four = 0x15
    case six = 0x16
    case five = 0x17
    case nine = 0x19
    case seven = 0x1A
    case eight = 0x1C
    case zero = 0x1D
    case o = 0x1F
    case u = 0x20
    case i = 0x22
    case p = 0x23
    case l = 0x25
    case j = 0x26
    case k = 0x28
    case n = 0x2D
    case m = 0x2E
    case returnKey = 0x24
    case tab = 0x30
    case space = 0x31
    case delete = 0x33
    case escape = 0x35
}
