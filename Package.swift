// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "SwiftJunkMacro",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .macCatalyst(.v13)],
    products: [
        .library(name: "SwiftJunkMacro", targets: ["SwiftJunkMacro"]),
        .library(name: "JunkGenerator", targets: ["JunkGenerator"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"603.0.0"),
    ],
    targets: [
        // Pure-Swift source generator. No swift-syntax dependency, so it can be
        // reused outside of the macro (e.g. to dump fixtures to a file).
        .target(name: "JunkGenerator"),

        // Compiler plugin: parses `@Junk(...)` arguments and feeds JunkGenerator.
        .macro(
            name: "SwiftJunkMacroMacros",
            dependencies: [
                "JunkGenerator",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),

        // What users import: the macro declaration and its supporting types.
        .target(name: "SwiftJunkMacro", dependencies: ["SwiftJunkMacroMacros"]),

        // Sample usage; also used to measure the effect on binary size.
        .executableTarget(name: "SwiftJunkMacroClient", dependencies: ["SwiftJunkMacro"]),

        .testTarget(name: "JunkGeneratorTests", dependencies: ["JunkGenerator"]),
        .testTarget(
            name: "SwiftJunkMacroTests",
            dependencies: [
                "SwiftJunkMacro",
                "SwiftJunkMacroMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
