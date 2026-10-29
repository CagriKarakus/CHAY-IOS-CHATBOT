import Foundation
import Testing
@testable import AgentCore

@Test(arguments: [
    ("2^10", "2**10"),
    ("(1250 * 0.18) + sqrt(144)", "(1250 * 0.18) + Math.sqrt(144)"),
    ("max(3, PI)", "Math.max(3, Math.PI)"),
    ("10 % 3", "10 % 3"),
])
func translatesAllowedExpressions(_ input: String, _ expected: String) throws {
    #expect(try CalculatorTool.validated(input) == expected)
}

@Test(arguments: [
    "while(true){}",
    "fetch('https://x')",
    "alert(1)",
    "x = 5",
    "constructor",
    "1; 2",
    "`a`",
    "Math.sqrt(4)",
    "",
])
func rejectsCode(_ input: String) {
    #expect(throws: (any Error).self) {
        try CalculatorTool.validated(input)
    }
}

@Test func runsWithInjectedEvaluator() async throws {
    let tool = CalculatorTool { script in
        #expect(script == "Math.sqrt(16) + 1")
        return 5
    }

    let output = try await tool.run(arguments: #"{"expression":"sqrt(16) + 1"}"#)

    #expect(output.content == "sqrt(16) + 1 = 5")
    #expect(tool.activityDetail(for: #"{"expression":"1+1"}"#) == "1+1")
}

@Test func rejectsNonFiniteResults() async throws {
    let tool = CalculatorTool { _ in .infinity }

    await #expect(throws: CalculatorTool.CalculatorError.invalidResult) {
        try await tool.run(arguments: #"{"expression":"1/0"}"#)
    }
}

@Test func formatsResults() {
    #expect(CalculatorTool.format(1024) == "1024")
    #expect(CalculatorTool.format(0.1 + 0.2) == "0.3")
    #expect(CalculatorTool.format(1.0 / 3.0) == "0.3333333333")
}
