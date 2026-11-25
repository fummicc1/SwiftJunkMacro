import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(SwiftJunkMacroMacros)
import SwiftJunkMacroMacros

private let macros: [String: Macro.Type] = ["Junk": JunkMacro.self]
#endif

final class JunkMacroTests: XCTestCase {
    private func skipIfUnavailable() throws {
        #if !canImport(SwiftJunkMacroMacros)
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testExpansionSnapshot() throws {
        try skipIfUnavailable()
        #if canImport(SwiftJunkMacroMacros)
        assertMacroExpansion(
            """
            @Junk(stored: 3, of: [.int, .string], computed: 1, methods: 1, keepAlive: true, seed: 1)
            struct Foo {
                var id: Int
            }
            """,
            expandedSource: """
            struct Foo {
                var id: Int

                var __junk_s0: Int = 652893

                var __junk_s1: String = "h4lv6jvak78ukex13cakm761"

                var __junk_s2: Int = 431537

                var __junk_c0: Int {
                    __junk_s0 &* 780523 &+ 64058
                }

                @inline(never) func __junk_m0(_ x: Int) -> Int {
                    var r = x
                    r ^= 709635
                    r ^= 238663
                    r ^= r << 12
                    r = r &* 819847
                    return r
                }

                @inline(never) func __junkKeepAlive() -> Int {
                    var r = 0
                    r = r &+ __junk_s0
                    r = r &+ __junk_s1.utf8.count
                    r = r &+ __junk_s2
                    r = r &+ __junk_c0
                    r = __junk_m0(r)
                    return r
                }
            }
            """,
            macros: macros
        )
        #endif
    }

    func testDefaultsGenerateEightInts() throws {
        try skipIfUnavailable()
        #if canImport(SwiftJunkMacroMacros)
        assertMacroExpansion(
            """
            @Junk
            final class Foo {
            }
            """,
            expandedSource: """
            final class Foo {

                var __junk_s0: Int = 669306

                var __junk_s1: Int = 553394

                var __junk_s2: Int = 210331

                var __junk_s3: Int = 700635

                var __junk_s4: Int = 986452

                var __junk_s5: Int = 70258

                var __junk_s6: Int = 164121

                var __junk_s7: Int = 870187
            }
            """,
            macros: macros
        )
        #endif
    }

    func testAccessLevelAndActor() throws {
        try skipIfUnavailable()
        #if canImport(SwiftJunkMacroMacros)
        assertMacroExpansion(
            """
            @Junk(stored: 1, of: [.object], access: .private, seed: 0x10)
            actor Foo {
            }
            """,
            expandedSource: """
            actor Foo {

                private var __junk_s0: SwiftJunkMacro.JunkObject = SwiftJunkMacro.JunkObject(683805)
            }
            """,
            macros: macros
        )
        #endif
    }

    func testRejectsEnum() throws {
        try skipIfUnavailable()
        #if canImport(SwiftJunkMacroMacros)
        assertMacroExpansion(
            """
            @Junk
            enum Foo {
            }
            """,
            expandedSource: """
            enum Foo {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Junk can only be attached to a struct, class or actor", line: 1, column: 1
                )
            ],
            macros: macros
        )
        #endif
    }

    func testRejectsNonLiteralCount() throws {
        try skipIfUnavailable()
        #if canImport(SwiftJunkMacroMacros)
        assertMacroExpansion(
            """
            @Junk(stored: n)
            struct Foo {
            }
            """,
            expandedSource: """
            struct Foo {
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "expected a non-negative integer literal", line: 1, column: 15)
            ],
            macros: macros
        )
        #endif
    }

    func testRejectsUnknownKind() throws {
        try skipIfUnavailable()
        #if canImport(SwiftJunkMacroMacros)
        assertMacroExpansion(
            """
            @Junk(of: [.float])
            struct Foo {
            }
            """,
            expandedSource: """
            struct Foo {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "unknown junk type; use a JunkType case such as .int", line: 1, column: 12
                )
            ],
            macros: macros
        )
        #endif
    }

    func testRejectsNameClash() throws {
        try skipIfUnavailable()
        #if canImport(SwiftJunkMacroMacros)
        assertMacroExpansion(
            """
            @Junk(stored: 2)
            struct Foo {
                var __junk_s1 = 0
            }
            """,
            expandedSource: """
            struct Foo {
                var __junk_s1 = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Junk would generate '__junk_s1', which 'Foo' already declares", line: 1, column: 1
                )
            ],
            macros: macros
        )
        #endif
    }
}
