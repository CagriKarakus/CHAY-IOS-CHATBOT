import AgentCore
import JavaScriptCore

/// `CalculatorTool` için hesap motoru. İfade AgentCore'da izin listesinden geçmiş olarak gelir;
/// her hesap ağ ve dosya erişimi olmayan, yeni ve boş bir JavaScript bağlamında yapılır.
let javaScriptCalculator: CalculatorTool.Evaluator = { script in
    guard let context = JSContext(),
          let value = context.evaluateScript(script),
          context.exception == nil,
          value.isNumber
    else { throw CalculatorTool.CalculatorError.invalidResult }
    return value.toDouble()
}
