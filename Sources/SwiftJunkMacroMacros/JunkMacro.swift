import JunkGenerator
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct JunkMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let typeName: String
        if let decl = declaration.as(StructDeclSyntax.self) {
            typeName = decl.name.text
        } else if let decl = declaration.as(ClassDeclSyntax.self) {
            typeName = decl.name.text
        } else if let decl = declaration.as(ActorDeclSyntax.self) {
            typeName = decl.name.text
        } else {
            throw JunkError(node: Syntax(node), "@Junk can only be attached to a struct, class or actor")
        }

        let config = try configuration(from: node, typeName: typeName)

        let existing = existingMemberNames(of: declaration)
        if let clash = JunkGenerator.memberNames(for: config).first(where: existing.contains) {
            throw JunkError(
                node: Syntax(node),
                "@Junk would generate '\(clash)', which '\(typeName)' already declares"
            )
        }

        return JunkGenerator.members(for: config).map { "\(raw: $0)" }
    }

    private static func configuration(
        from node: AttributeSyntax,
        typeName: String
    ) throws -> JunkConfiguration {
        var config = JunkConfiguration(seed: JunkGenerator.defaultSeed(for: typeName))
        guard case .argumentList(let arguments) = node.arguments else { return config }

        for argument in arguments {
            let value = argument.expression
            switch argument.label?.text {
            case "stored": config.stored = try count(value)
            case "computed": config.computed = try count(value)
            case "methods": config.methods = try count(value)
            case "of":
                guard let array = value.as(ArrayExprSyntax.self), !array.elements.isEmpty else {
                    throw JunkError(node: Syntax(value), "'of' must be a non-empty array literal such as [.int, .string]")
                }
                config.kinds = try array.elements.map { element in
                    guard let kind = caseName(element.expression).flatMap(JunkKind.init(rawValue:)) else {
                        throw JunkError(node: Syntax(element.expression), "unknown junk type; use a JunkType case such as .int")
                    }
                    return kind
                }
            case "access":
                guard let access = caseName(value).flatMap(JunkAccessLevel.init(rawValue:)) else {
                    throw JunkError(node: Syntax(value), "'access' must be a JunkAccess case such as .private")
                }
                config.access = access
            case "keepAlive":
                guard let literal = value.as(BooleanLiteralExprSyntax.self) else {
                    throw JunkError(node: Syntax(value), "'keepAlive' must be a boolean literal")
                }
                config.keepAlive = literal.literal.tokenKind == .keyword(.true)
            case "seed":
                if value.is(NilLiteralExprSyntax.self) { continue }
                guard let seed = integer(value, as: UInt64.self) else {
                    throw JunkError(node: Syntax(value), "'seed' must be an integer literal")
                }
                config.seed = seed
            default:
                break
            }
        }
        return config
    }

    private static func count(_ expression: ExprSyntax) throws -> Int {
        guard let value = integer(expression, as: Int.self), value >= 0 else {
            throw JunkError(node: Syntax(expression), "expected a non-negative integer literal")
        }
        return value
    }

    private static func integer<T: FixedWidthInteger>(_ expression: ExprSyntax, as type: T.Type) -> T? {
        guard let literal = expression.as(IntegerLiteralExprSyntax.self) else { return nil }
        let text = literal.literal.text.filter { $0 != "_" }
        for (prefix, radix) in [("0x", 16), ("0b", 2), ("0o", 8)] where text.hasPrefix(prefix) {
            return T(text.dropFirst(2), radix: radix)
        }
        return T(text)
    }

    /// `.int` or `JunkType.int` -> `"int"`.
    private static func caseName(_ expression: ExprSyntax) -> String? {
        expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
            .trimmingBackticks
    }

    private static func existingMemberNames(of declaration: some DeclGroupSyntax) -> Set<String> {
        var names: Set<String> = []
        for member in declaration.memberBlock.members {
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                for binding in variable.bindings {
                    if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        names.insert(pattern.identifier.text)
                    }
                }
            } else if let function = member.decl.as(FunctionDeclSyntax.self) {
                names.insert(function.name.text)
            }
        }
        return names
    }
}

private extension String {
    var trimmingBackticks: String { filter { $0 != "`" } }
}

struct JunkMessage: DiagnosticMessage {
    let message: String
    var diagnosticID: MessageID { MessageID(domain: "SwiftJunkMacro", id: "junk") }
    var severity: DiagnosticSeverity { .error }
}

/// An error that is reported at `node` rather than at the whole attribute.
func JunkError(node: Syntax, _ message: String) -> DiagnosticsError {
    DiagnosticsError(diagnostics: [Diagnostic(node: node, message: JunkMessage(message: message))])
}

@main
struct SwiftJunkMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [JunkMacro.self]
}
