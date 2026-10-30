import Foundation

/// Matematik ifadelerini hesaplayan araç; modellerin aritmetik hatalarını önler.
/// İfade önce izin listesiyle doğrulanır (sayılar, işlemler, `Math` fonksiyonları);
/// döngü, değişken veya başka kod yazılamaz. Hesabı uygulama tarafındaki motor yapar (iOS'ta JavaScriptCore).
public struct CalculatorTool: Tool {
    public typealias Evaluator = @Sendable (String) throws -> Double

    private struct Arguments: Decodable {
        let expression: String
    }

    public enum CalculatorError: Error, Equatable, Sendable {
        case notAllowed(String)
        case invalidResult
    }

    /// İfadede kullanılabilen fonksiyon ve sabitler (JavaScript `Math` nesnesi).
    static let allowedNames: Set<String> = [
        "abs", "acos", "acosh", "asin", "asinh", "atan", "atan2", "atanh", "cbrt", "ceil", "cos", "cosh",
        "exp", "expm1", "floor", "hypot", "log", "log10", "log1p", "log2", "max", "min", "pow", "round",
        "sign", "sin", "sinh", "sqrt", "tan", "tanh", "trunc", "PI", "E", "LN2", "LN10", "SQRT2",
    ]
    static let maxLength = 500

    public let name = "calculate"
    public let description = "Evaluates a math expression exactly. Use it for any arithmetic, percentages, unit math or formulas instead of calculating in your head. Supports + - * / % ^ ( ) and functions like sqrt, pow, sin, cos, tan, log, log10, exp, abs, round, floor, ceil, min, max and constants PI, E."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "expression": ["type": "string", "description": "Math expression, e.g. '(1250 * 0.18) + sqrt(144)' or '2^10'"],
        ],
        "required": ["expression"],
    ]

    private let evaluate: Evaluator

    public init(evaluate: @escaping Evaluator) {
        self.evaluate = evaluate
    }

    public func activityDetail(for arguments: String) -> String? {
        (try? decodeArguments(Arguments.self, from: arguments))?.expression
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let expression = try decodeArguments(Arguments.self, from: arguments).expression
        let script = try Self.validated(expression)
        let value = try evaluate(script)
        guard value.isFinite else { throw CalculatorError.invalidResult }
        return ToolOutput(content: "\(expression) = \(Self.format(value))")
    }

    /// İfadeyi doğrular ve motorun çalıştıracağı JavaScript'e çevirir (`^` → `**`, fonksiyonlar → `Math.`).
    static func validated(_ expression: String) throws -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { throw CalculatorError.notAllowed(expression) }

        let symbols = Set("0123456789.,+-*/%^() \t")
        var output = ""
        /// Açık parantezler; `true` ise fonksiyon çağrısı.
        var parentheses: [Bool] = []
        var afterName = false
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if character.isLetter || character == "_" {
                var end = index
                while end < trimmed.endIndex, trimmed[end].isLetter || trimmed[end].isNumber || trimmed[end] == "_" {
                    end = trimmed.index(after: end)
                }
                let word = String(trimmed[index..<end])
                guard allowedNames.contains(word) else { throw CalculatorError.notAllowed(word) }
                output += "Math." + word
                index = end
                afterName = true
                continue
            }
            guard symbols.contains(character) else { throw CalculatorError.notAllowed(String(character)) }
            let next = trimmed.index(after: index)
            let previous = output.last { !$0.isWhitespace }
            switch character {
            case ",":
                // Virgül sadece fonksiyon argümanlarını ayırır: JavaScript `1,000+2` ifadesini sessizce 2 hesaplar.
                guard parentheses.last == true else { throw CalculatorError.notAllowed(",") }
            case "(":
                parentheses.append(afterName)
            case ")":
                _ = parentheses.popLast()
            case "0" where next < trimmed.endIndex && trimmed[next].isNumber && output.last?.isNumber != true && output.last != ".":
                // JavaScript `010` ifadesini 8 sayar.
                throw CalculatorError.notAllowed(String(trimmed[index...].prefix(2)))
            default:
                break
            }
            if character == "-", previous == nil || previous == "(" || previous == "," {
                // JavaScript `-2**2` yazımını reddeder; matematikte sonuç -(2^2)'dir.
                output += "(-1)*"
            } else {
                output += character == "^" ? "**" : String(character)
            }
            if !character.isWhitespace { afterName = false }
            index = next
        }
        return output
    }

    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.10g", value)
    }
}

extension CalculatorTool.CalculatorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .notAllowed(part):
            return "Not allowed in a math expression: '\(part)'. Use numbers, + - * / % ^ ( ) and Math functions only."
        case .invalidResult:
            return "The result is not a finite number (e.g. division by zero)."
        }
    }
}
