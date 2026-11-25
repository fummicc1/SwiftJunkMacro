/// The type of a generated stored property.
///
/// The cases are chosen to cover the cost classes that matter when measuring
/// copies and layout: trivially copyable values versus reference-counted ones.
public enum JunkKind: String, CaseIterable, Sendable {
    /// `Int` — trivially copyable, one word.
    case int
    /// `Double` — trivially copyable, 8 bytes.
    case double
    /// `Bool` — trivially copyable, 1 byte (introduces padding next to wider fields).
    case bool
    /// `String` longer than 15 UTF-8 bytes, so it is heap-allocated and reference-counted.
    case string
    /// `[Int]` — one reference-counted buffer.
    case array
    /// `SwiftJunkMacro.JunkObject` — a class reference.
    case object

    var typeName: String {
        switch self {
        case .int: "Int"
        case .double: "Double"
        case .bool: "Bool"
        case .string: "String"
        case .array: "[Int]"
        case .object: "SwiftJunkMacro.JunkObject"
        }
    }
}

/// Access level applied to every generated member.
public enum JunkAccessLevel: String, CaseIterable, Sendable {
    case `private`, `fileprivate`, `internal`, `package`, `public`

    var prefix: String { self == .internal ? "" : rawValue + " " }
}

/// Everything that determines the generated members. Equal configurations
/// always produce identical source.
public struct JunkConfiguration: Equatable, Sendable {
    /// Number of stored properties.
    public var stored: Int
    /// Types of the stored properties, applied round-robin.
    public var kinds: [JunkKind]
    /// Number of computed properties.
    public var computed: Int
    /// Number of methods.
    public var methods: Int
    public var access: JunkAccessLevel
    /// Also generate `__junkKeepAlive()`, which touches every generated member.
    public var keepAlive: Bool
    /// Seed for the generated values and method bodies.
    public var seed: UInt64

    public init(
        stored: Int = 8,
        kinds: [JunkKind] = [.int],
        computed: Int = 0,
        methods: Int = 0,
        access: JunkAccessLevel = .internal,
        keepAlive: Bool = false,
        seed: UInt64
    ) {
        self.stored = stored
        self.kinds = kinds
        self.computed = computed
        self.methods = methods
        self.access = access
        self.keepAlive = keepAlive
        self.seed = seed
    }
}

public enum JunkGenerator {
    public static let keepAliveName = "__junkKeepAlive"

    public static func storedName(_ index: Int) -> String { "__junk_s\(index)" }
    public static func computedName(_ index: Int) -> String { "__junk_c\(index)" }
    public static func methodName(_ index: Int) -> String { "__junk_m\(index)" }

    /// A seed derived from a type name (FNV-1a). Stable across processes and
    /// platforms, unlike `Hasher`.
    public static func defaultSeed(for typeName: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in typeName.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// The names of all members `members(for:)` will declare.
    public static func memberNames(for config: JunkConfiguration) -> [String] {
        var names = (0..<max(config.stored, 0)).map(storedName)
        names += (0..<max(config.computed, 0)).map(computedName)
        names += (0..<max(config.methods, 0)).map(methodName)
        if config.keepAlive { names.append(keepAliveName) }
        return names
    }

    /// Source text of each member declaration, in declaration order.
    public static func members(for config: JunkConfiguration) -> [String] {
        // Independent streams, so that changing one count does not reshuffle
        // the values generated for the other kinds of member.
        var storedRNG = SplitMix64(seed: config.seed)
        var computedRNG = SplitMix64(seed: config.seed ^ 0x9e37_79b9_7f4a_7c15)
        var methodRNG = SplitMix64(seed: config.seed ^ 0xc2b2_ae3d_27d4_eb4f)

        let access = config.access.prefix
        let kinds = config.kinds.isEmpty ? [.int] : config.kinds
        var result: [String] = []
        var storedKinds: [JunkKind] = []

        for index in 0..<max(config.stored, 0) {
            let kind = kinds[index % kinds.count]
            storedKinds.append(kind)
            // `var`, not `let`: synthesized `Decodable` skips initialized `let`s.
            result.append(
                "\(access)var \(storedName(index)): \(kind.typeName) = \(literal(of: kind, using: &storedRNG))"
            )
        }

        let intIndices = storedKinds.indices.filter { storedKinds[$0] == .int }
        for index in 0..<max(config.computed, 0) {
            let multiplier = computedRNG.constant() | 1
            let addend = computedRNG.constant()
            let body: String
            if intIndices.isEmpty {
                body = "\(multiplier) &+ \(addend)"
            } else {
                let source = intIndices[computedRNG.next(below: intIndices.count)]
                body = "\(storedName(source)) &* \(multiplier) &+ \(addend)"
            }
            result.append("\(access)var \(computedName(index)): Int { \(body) }")
        }

        for index in 0..<max(config.methods, 0) {
            // Bodies differ in shape, not just in constants, so the optimizer
            // cannot merge them into one parameterized function.
            var lines = ["var r = x"]
            for _ in 0..<(3 + methodRNG.next(below: 4)) {
                lines.append(operation(using: &methodRNG))
            }
            lines.append("return r")
            result.append(
                """
                @inline(never) \(access)func \(methodName(index))(_ x: Int) -> Int {
                \(lines.joined(separator: "\n"))
                }
                """
            )
        }

        if config.keepAlive {
            var lines = ["var r = 0"]
            for (index, kind) in storedKinds.enumerated() {
                lines.append("r = r &+ \(intValue(of: storedName(index), kind: kind))")
            }
            for index in 0..<max(config.computed, 0) {
                lines.append("r = r &+ \(computedName(index))")
            }
            for index in 0..<max(config.methods, 0) {
                lines.append("r = \(methodName(index))(r)")
            }
            lines.append("return r")
            result.append(
                """
                @inline(never) \(access)func \(keepAliveName)() -> Int {
                \(lines.joined(separator: "\n"))
                }
                """
            )
        }

        return result
    }

    private static func literal(of kind: JunkKind, using rng: inout SplitMix64) -> String {
        switch kind {
        case .int:
            return "\(rng.constant())"
        case .double:
            let fraction = String(rng.next(below: 1000))
            let padding = String(repeating: "0", count: 3 - fraction.count)
            return "\(rng.constant()).\(padding)\(fraction)"
        case .bool:
            return rng.next(below: 2) == 0 ? "false" : "true"
        case .string:
            // 24 bytes: above the 15-byte small-string limit.
            let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
            let text = String((0..<24).map { _ in alphabet[rng.next(below: alphabet.count)] })
            return "\"\(text)\""
        case .array:
            return "[\((0..<4).map { _ in String(rng.constant()) }.joined(separator: ", "))]"
        case .object:
            return "SwiftJunkMacro.JunkObject(\(rng.constant()))"
        }
    }

    private static func intValue(of name: String, kind: JunkKind) -> String {
        switch kind {
        case .int: name
        case .double: "Int(truncatingIfNeeded: \(name).bitPattern)"
        case .bool: "(\(name) ? 1 : 0)"
        case .string: "\(name).utf8.count"
        case .array: "\(name).count"
        case .object: "\(name).value"
        }
    }

    private static func operation(using rng: inout SplitMix64) -> String {
        let shift = 1 + rng.next(below: 13)
        switch rng.next(below: 6) {
        case 0: return "r = r &* \(rng.constant() | 1)"
        case 1: return "r = r &+ \(rng.constant())"
        case 2: return "r = r &- \(rng.constant())"
        case 3: return "r ^= \(rng.constant())"
        case 4: return "r ^= r >> \(shift)"
        default: return "r ^= r << \(shift)"
        }
    }
}

/// Small deterministic PRNG; `SystemRandomNumberGenerator` cannot be seeded.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    mutating func next(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }

    /// A non-negative constant that fits in a 32-bit `Int` (watchOS arm64_32).
    mutating func constant() -> Int {
        1 + next(below: 999_999)
    }
}
