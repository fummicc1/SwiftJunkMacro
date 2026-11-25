# SwiftJunkMacro

Create junk variables in your class.

`@Junk` is a Swift macro that adds synthetic members to a struct, class or
actor. It is meant for building **test fixtures for performance work**: types
with a controlled number of fields, of a controlled cost class, without
writing them by hand.

```swift
import SwiftJunkMacro

@Junk(stored: 64, of: [.int, .string])
struct Payload {
    var id: Int
}
```

expands to

```swift
struct Payload {
    var id: Int

    var __junk_s0: Int = 652893
    var __junk_s1: String = "h4lv6jvak78ukex13cakm761"
    var __junk_s2: Int = 431537
    // ... 64 in total
}
```

Change one number to compare 8, 64 and 512 fields; change `of:` to compare
trivially copyable fields against reference-counted ones.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/fummicc1/SwiftJunkMacro.git", branch: "main"),
],
targets: [
    .target(name: "MyBenchmarks", dependencies: ["SwiftJunkMacro"]),
]
```

Requires Swift 6.0 or later.

## Options

All arguments must be literals, because the macro reads them at compile time.

| Argument | Default | Meaning |
|---|---|---|
| `stored:` | `8` | Number of stored properties (`__junk_s0`, ...). |
| `of:` | `[.int]` | Types of the stored properties, applied round-robin. |
| `computed:` | `0` | Number of computed `Int` properties (`__junk_c0`, ...). |
| `methods:` | `0` | Number of `@inline(never)` methods (`__junk_m0(_:)`, ...). |
| `access:` | `.internal` | Access level of every generated member. |
| `keepAlive:` | `false` | Also generate `__junkKeepAlive()`, which reads every generated member. |
| `seed:` | hash of the type name | Seed for the generated values and method bodies. |

### Field types

| Case | Swift type | Copy cost |
|---|---|---|
| `.int` | `Int` | trivial |
| `.double` | `Double` | trivial |
| `.bool` | `Bool` | trivial; 1 byte, so it introduces padding |
| `.string` | `String` (24 bytes of text, above the small-string limit) | retain/release |
| `.array` | `[Int]` | retain/release |
| `.object` | `JunkObject` (a final class) | retain/release |

## Things to know

**The expansion is deterministic.** The same arguments on a type of the same
name always produce the same source, so before/after measurements compare the
same code and build caches stay valid. Pass `seed:` to get a different variant.

**Stored properties work with existing code.** Each has an initial value, so
your initializers keep compiling, and synthesized `Equatable`, `Hashable` and
`Codable` conformances include the junk fields. With `access: .private` or
`.fileprivate`, a struct's implicit memberwise initializer becomes equally
restricted — that is a Swift rule, not something the macro can avoid.

**Unused methods and computed properties are removed from optimized builds.**
Stored properties always affect the type's layout, but code that nothing calls
is dropped by the optimizer and linker. To measure binary size, either make the
members `public` on a `public` type, or pass `keepAlive: true` and call
`__junkKeepAlive()` from code that is itself used.

Measured with Swift 6.2.4 on Linux x86_64, `@Junk(stored: 0, computed: 200,
methods: 200)` on a struct in an executable (size of the text segment, bytes):

| Variant | Debug | Release | Junk symbols in release |
|---|---:|---:|---:|
| no `@Junk` | 77,194 | 15,466 | 0 |
| `access: .private`, unused | 203,586 | 15,466 | 0 |
| `access: .internal`, unused | 200,546 | 15,466 | 0 |
| `access: .public` on a `public` struct | 200,370 | 43,927 | 600 |
| `keepAlive: true`, not called | 210,482 | 15,466 | 0 |
| `keepAlive: true`, called | 210,614 | 34,361 | 200 |

In the last row the 200 methods remain as symbols and the computed properties
are inlined into `__junkKeepAlive()`. Apple platforms use a different linker,
so check with `nm` on your own target.

**Macro expansion is part of the build.** When measuring compile time, the
cost of expanding `@Junk` is included. To measure the type checker alone,
generate the source ahead of time with the `JunkGenerator` library, which the
macro itself is built on:

```swift
import JunkGenerator

let members = JunkGenerator.members(
    for: JunkConfiguration(stored: 512, kinds: [.int], seed: 1)
)
```

## Development

```sh
swift build
swift test
swift run SwiftJunkMacroClient
```
