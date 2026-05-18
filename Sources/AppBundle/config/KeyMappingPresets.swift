import Common
import HotKey

let minus = "minus"
let equal = "equal"

let q = "q"
let w = "w"
let e = "e"
let r = "r"
let t = "t"
let y = "y"
let u = "u"
let i = "i"
let o = "o"
let p = "p"
let leftSquareBracket = "leftSquareBracket"
let rightSquareBracket = "rightSquareBracket"
let backslash = "backslash"
let sectionSign = "sectionSign"

let a = "a"
let s = "s"
let d = "d"
let f = "f"
let g = "g"
let h = "h"
let j = "j"
let k = "k"
let l = "l"
let semicolon = "semicolon"
let quote = "quote"

let z = "z"
let x = "x"
let c = "c"
let v = "v"
let b = "b"
let n = "n"
let m = "m"
let comma = "comma"
let period = "period"
let slash = "slash"

func getKeysPreset(_ layout: KeyMapping.Preset) -> [String: Key] {
    return switch layout {
        case .qwerty: keyNotationToKeyCode
        case .dvorak: dvorakMap
        case .colemak: colemakMap
    }
}

extension Key: @unchecked @retroactive Sendable {}

let keyNotationToKeyCode: [String: Key] = {
    var result = standardKeyMap
    result = result + keypadKeyMap
    result = result + navigationKeyMap
    result = result + functionKeyMap
    result = result + specialKeyMap
    return result
}()

private let standardKeyMap: [String: Key] = [
    sectionSign: .section,
    "0": .zero,
    "1": .one,
    "2": .two,
    "3": .three,
    "4": .four,
    "5": .five,
    "6": .six,
    "7": .seven,
    "8": .eight,
    "9": .nine,
    minus: .minus,
    equal: .equal,

    q: .q,
    w: .w,
    e: .e,
    r: .r,
    t: .t,
    y: .y,
    u: .u,
    i: .i,
    o: .o,
    p: .p,
    leftSquareBracket: .leftBracket,
    rightSquareBracket: .rightBracket,
    backslash: .backslash,

    a: .a,
    s: .s,
    d: .d,
    f: .f,
    g: .g,
    h: .h,
    j: .j,
    k: .k,
    l: .l,
    semicolon: .semicolon,
    quote: .quote,

    z: .z,
    x: .x,
    c: .c,
    v: .v,
    b: .b,
    n: .n,
    m: .m,
    comma: .comma,
    period: .period,
    slash: .slash,
]

private let keypadKeyMap: [String: Key] = [
    "keypad0": .keypad0,
    "keypad1": .keypad1,
    "keypad2": .keypad2,
    "keypad3": .keypad3,
    "keypad4": .keypad4,
    "keypad5": .keypad5,
    "keypad6": .keypad6,
    "keypad7": .keypad7,
    "keypad8": .keypad8,
    "keypad9": .keypad9,
    "keypadClear": .keypadClear,
    "keypadDecimalMark": .keypadDecimal,
    "keypadDivide": .keypadDivide,
    "keypadEnter": .keypadEnter,
    "keypadEqual": .keypadEquals,
    "keypadMinus": .keypadMinus,
    "keypadMultiply": .keypadMultiply,
    "keypadPlus": .keypadPlus,
]

private let navigationKeyMap: [String: Key] = [
    "pageUp": .pageUp,
    "pageDown": .pageDown,
    "home": .home,
    "end": .end,
    "forwardDelete": .forwardDelete,
    "left": .leftArrow,
    "down": .downArrow,
    "up": .upArrow,
    "right": .rightArrow,
]

private let functionKeyMap: [String: Key] = [
    "f1": .f1,
    "f2": .f2,
    "f3": .f3,
    "f4": .f4,
    "f5": .f5,
    "f6": .f6,
    "f7": .f7,
    "f8": .f8,
    "f9": .f9,
    "f10": .f10,
    "f11": .f11,
    "f12": .f12,
    "f13": .f13,
    "f14": .f14,
    "f15": .f15,
    "f16": .f16,
    "f17": .f17,
    "f18": .f18,
    "f19": .f19,
    "f20": .f20,
]

private let specialKeyMap: [String: Key] = [
    "backtick": .grave,
    "space": .space,
    "enter": .return,
    "esc": .escape,
    "backspace": .delete,
    "tab": .tab,
]
