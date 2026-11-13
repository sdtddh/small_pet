// MathExpression.swift —— 計算機用的算式解析：把「2(3+4)^2 ÷ log 100」這種字串算成數字。
//
// 支援：
//   + − × ÷（也可以打 * /）、括號、^ 次方（右結合：2^3^2 = 2^9）、% 百分比（50% = 0.5）
//   函數：log（以 10 為底）、ln、√ / sqrt、abs；括號可省略：log 100、√9
//   常數：π / pi、e
//   隱藏的乘號：2π、3(4+1)、(1+2)(3+4)、2log 100
// 運算順序：括號 → 函數 → 次方 → 正負號 → 乘除 → 加減。所以 -2^2 = -4、2^-1 = 0.5。
// 這個檔案不依賴 AppKit，可以單獨拿去測試。
import Foundation

enum ExpressionError: Error, Equatable, CustomStringConvertible {
    case empty
    case incomplete                  // 算式還沒打完，例如「3+」、「(2」
    case unexpected(String)          // 看不懂的符號
    case unknownName(String)         // 不認識的函數 / 常數
    case divideByZero
    case domain(String)              // 數學上沒有定義，例如 log(-1)、√-4
    case overflow                    // 結果太大

    var description: String {
        switch self {
        case .empty: ""
        case .incomplete: "算式還沒打完"
        case .unexpected(let s): "看不懂「\(s)」"
        case .unknownName(let s): "不認識「\(s)」"
        case .divideByZero: "不能除以 0"
        case .domain(let s): s
        case .overflow: "數字太大了"
        }
    }
}

enum MathExpression {

    static func evaluate(_ text: String) throws -> Double {
        var parser = Parser(tokens: try tokenize(normalize(text)))
        guard !parser.tokens.isEmpty else { throw ExpressionError.empty }
        let value = try parser.expression()
        if let extra = parser.peek { throw extra == .close ? ExpressionError.unexpected(")") : ExpressionError.unexpected(extra.text) }
        guard value.isFinite else { throw ExpressionError.overflow }
        return value == 0 ? 0 : value   // 不要顯示 -0
    }

    // 顯示用：最多 12 位有效數字，去掉多餘的 0；太大或太小用科學記號。
    static func format(_ value: Double) -> String {
        let a = abs(value)
        if a == 0 { return "0" }
        if a < 1e15, value == value.rounded() { return String(Int64(value)) }   // 整數完整顯示
        if a >= 1e15 || a < 1e-9 {
            return String(format: "%.10g", value).replacingOccurrences(of: "e+", with: "e")
        }
        return String(format: "%.12g", value)
    }

    // 全形、數學符號換成 ASCII。
    static func normalize(_ text: String) -> String {
        var s = text
        for (a, b) in [("×", "*"), ("·", "*"), ("÷", "/"), ("−", "-"), ("–", "-"), ("＋", "+"), ("－", "-"),
                       ("＊", "*"), ("／", "/"), ("（", "("), ("）", ")"), ("＾", "^"), ("％", "%"), ("，", ","), ("．", ".")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        // 全形數字
        return String(s.unicodeScalars.map { u in
            (0xFF10...0xFF19).contains(u.value) ? Swift.Character(UnicodeScalar(u.value - 0xFF10 + 0x30)!) : Swift.Character(u)
        })
    }

    // MARK: - 切成記號

    enum Token: Equatable {
        case number(Double)
        case name(String)
        case op(Swift.Character)      // + - * / ^ %
        case open, close

        var text: String {
            switch self {
            case .number(let v): MathExpression.format(v)
            case .name(let n): n
            case .op(let c): String(c)
            case .open: "("
            case .close: ")"
            }
        }
    }

    static func tokenize(_ s: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isASCII && (c.isNumber || c == ".") {
                var j = i
                while j < chars.count, chars[j].isASCII, chars[j].isNumber || chars[j] == "." { j += 1 }
                // 科學記號：1e5、2.5e-3（e 後面一定要接數字，不然 e 是常數：2e = 2×e）
                if j < chars.count, chars[j] == "e" || chars[j] == "E" {
                    var k = j + 1
                    if k < chars.count, chars[k] == "+" || chars[k] == "-" { k += 1 }
                    if k < chars.count, chars[k].isASCII, chars[k].isNumber {
                        while k < chars.count, chars[k].isASCII, chars[k].isNumber { k += 1 }
                        j = k
                    }
                }
                let text = String(chars[i..<j])
                guard let v = Double(text) else { throw ExpressionError.unexpected(text) }
                tokens.append(.number(v))
                i = j
            } else if c.isLetter || c == "π" || c == "√" {
                // 名字：連續的英文字母；π、√ 自己就是一個名字
                if c == "π" || c == "√" { tokens.append(.name(String(c))); i += 1; continue }
                var j = i
                while j < chars.count, chars[j].isLetter, chars[j] != "π", chars[j] != "√" { j += 1 }
                tokens.append(contentsOf: try splitName(String(chars[i..<j]).lowercased()))
                i = j
            } else if "+-*/^%".contains(c) {
                tokens.append(.op(c)); i += 1
            } else if c == "(" {
                tokens.append(.open); i += 1
            } else if c == ")" {
                tokens.append(.close); i += 1
            } else {
                throw ExpressionError.unexpected(String(c))
            }
        }
        return tokens
    }

    static let functions: [String: @Sendable (Double) throws -> Double] = [
        "log": { x in
            guard x > 0 else { throw ExpressionError.domain("log 裡面要大於 0") }
            return log10(x)
        },
        "ln": { x in
            guard x > 0 else { throw ExpressionError.domain("ln 裡面要大於 0") }
            return Foundation.log(x)
        },
        "√": { x in
            guard x >= 0 else { throw ExpressionError.domain("√ 裡面不能是負數") }
            return x.squareRoot()
        },
        "abs": { abs($0) },
    ]
    static let aliases = ["sqrt": "√", "pi": "π", "lg": "log"]
    static let constants: [String: Double] = ["π": .pi, "e": M_E]

    // 「pie」「epi」這種黏在一起的常數拆開（2pie = 2×π×e）；認不出來就報錯。
    static func splitName(_ word: String) throws -> [Token] {
        var out: [Token] = []
        var rest = Substring(word)
        let names = (Array(functions.keys) + Array(aliases.keys) + Array(constants.keys)).sorted { $0.count > $1.count }
        while !rest.isEmpty {
            guard let n = names.first(where: { rest.hasPrefix($0) }) else { throw ExpressionError.unknownName(String(rest)) }
            out.append(.name(aliases[n] ?? n))
            rest = rest.dropFirst(n.count)
        }
        return out
    }

    // MARK: - 遞迴下降解析

    struct Parser {
        let tokens: [Token]
        var pos = 0

        var peek: Token? { pos < tokens.count ? tokens[pos] : nil }

        mutating func next() throws -> Token {
            guard let t = peek else { throw ExpressionError.incomplete }
            pos += 1
            return t
        }

        // 加減
        mutating func expression() throws -> Double {
            var v = try term()
            while case .op(let c)? = peek, c == "+" || c == "-" {
                pos += 1
                let r = try term()
                v = c == "+" ? v + r : v - r
            }
            return v
        }

        // 乘除，和省略的乘號（後面直接接數字、名字、左括號）
        mutating func term() throws -> Double {
            var v = try signed()
            while let t = peek {
                switch t {
                case .op("*"):
                    pos += 1; v *= try signed()
                case .op("/"):
                    pos += 1
                    let r = try signed()
                    guard r != 0 else { throw ExpressionError.divideByZero }
                    v /= r
                case .number, .name, .open:
                    v *= try power()
                default:
                    return v
                }
            }
            return v
        }

        // 正負號：-2^2 = -(2^2)
        mutating func signed() throws -> Double {
            if case .op(let c)? = peek, c == "-" || c == "+" {
                pos += 1
                let v = try signed()
                return c == "-" ? -v : v
            }
            return try power()
        }

        // 次方（右結合）；指數可以有正負號：2^-1
        mutating func power() throws -> Double {
            let base = try postfix()
            if case .op("^")? = peek {
                pos += 1
                let exp = try signed()
                let v = Foundation.pow(base, exp)
                if v.isNaN { throw ExpressionError.domain("負數不能開這個次方") }
                return v
            }
            return base
        }

        // 後面的 %：50% = 0.5
        mutating func postfix() throws -> Double {
            var v = try primary()
            while case .op("%")? = peek {
                pos += 1
                v /= 100
            }
            return v
        }

        mutating func primary() throws -> Double {
            switch try next() {
            case .number(let v):
                return v
            case .open:
                let v = try expression()
                // 少打的右括號自動補上（計算機常見的寬容做法）：(2+3 = 5
                if case .close? = peek { pos += 1 }
                return v
            case .name(let n):
                if let c = MathExpression.constants[n] { return c }
                guard let f = MathExpression.functions[n] else { throw ExpressionError.unknownName(n) }
                // 函數的參數：有括號就是括號裡的整個算式；沒括號就吃一個（可帶正負號的）次方，log 100 + 1 = 3
                return try f(try signed())
            case .op(let c):
                throw ExpressionError.unexpected(String(c))
            case .close:
                throw ExpressionError.unexpected(")")
            }
        }
    }
}
