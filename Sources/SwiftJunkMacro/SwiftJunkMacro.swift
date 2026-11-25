/// Adds synthetic ("junk") members to a struct, class or actor, to build
/// test fixtures for performance work: types with a controlled number of
/// fields, of a controlled cost class, without writing them by hand.
///
///     @Junk(stored: 64, of: [.int, .string])
///     struct Payload {}
///
/// Members are named `__junk_s<N>` (stored), `__junk_c<N>` (computed) and
/// `__junk_m<N>` (methods). The expansion is deterministic: the same
/// arguments on a type of the same name always produce the same source.
///
/// All arguments must be literals, because the macro reads them at compile time.
///
/// - Parameters:
///   - stored: Number of stored properties. Each has an initial value, so
///     existing initializers keep working.
///   - kinds: Types of the stored properties, applied round-robin.
///   - computed: Number of computed `Int` properties.
///   - methods: Number of `@inline(never)` methods.
///   - access: Access level of every generated member. Note that `private`
///     or `fileprivate` stored properties also restrict a struct's implicit
///     memberwise initializer.
///   - keepAlive: Also generate `__junkKeepAlive() -> Int`, which reads every
///     generated member. Unused members are removed from optimized builds;
///     call this once from code that is itself used to keep them in the binary.
///   - seed: Seed for the generated values and method bodies. Defaults to a
///     hash of the type's name.
@attached(member, names: arbitrary)
public macro Junk(
    stored: Int = 8,
    of kinds: [JunkType] = [.int],
    computed: Int = 0,
    methods: Int = 0,
    access: JunkAccess = .internal,
    keepAlive: Bool = false,
    seed: UInt64? = nil
) = #externalMacro(module: "SwiftJunkMacroMacros", type: "JunkMacro")

/// The type of a generated stored property.
public enum JunkType: Sendable {
    /// `Int` — trivially copyable.
    case int
    /// `Double` — trivially copyable.
    case double
    /// `Bool` — trivially copyable, 1 byte (introduces padding next to wider fields).
    case bool
    /// A `String` longer than 15 UTF-8 bytes, so it is heap-allocated and reference-counted.
    case string
    /// `[Int]` — one reference-counted buffer.
    case array
    /// ``JunkObject`` — a class reference.
    case object
}

/// Access level of the generated members.
public enum JunkAccess: Sendable {
    case `private`, `fileprivate`, `internal`, `package`, `public`
}

/// The class used for ``JunkType/object`` properties. Immutable, so that
/// types holding it can still be `Sendable`, `Hashable` and `Codable`.
public final class JunkObject: Sendable, Hashable, Codable {
    public let value: Int

    public init(_ value: Int) { self.value = value }

    public static func == (lhs: JunkObject, rhs: JunkObject) -> Bool { lhs.value == rhs.value }
    public func hash(into hasher: inout Hasher) { hasher.combine(value) }
}
