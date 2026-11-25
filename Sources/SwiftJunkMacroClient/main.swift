import SwiftJunkMacro

// Trivially copyable fields only: copying is a memcpy.
@Junk(stored: 64)
struct Trivial {}

// Reference-counted fields: every copy retains, every destroy releases.
@Junk(stored: 64, of: [.string, .array, .object])
struct RefCounted {}

// Junk members sit alongside real ones, and synthesized conformances see them.
@Junk(stored: 4, of: [.int, .bool], computed: 2, methods: 2, keepAlive: true)
struct Mixed: Hashable, Codable {
    var id: Int
}

@Junk(stored: 2, of: [.object], methods: 1, access: .private, seed: 42)
final class Model {}

@Junk(stored: 2, methods: 1)
actor Worker {}

print("Trivial:    size \(MemoryLayout<Trivial>.size), stride \(MemoryLayout<Trivial>.stride)")
print("RefCounted: size \(MemoryLayout<RefCounted>.size), stride \(MemoryLayout<RefCounted>.stride)")
print("Mixed:      size \(MemoryLayout<Mixed>.size), stride \(MemoryLayout<Mixed>.stride)")

let mixed = Mixed(id: 1)
print("Mixed keep-alive checksum: \(mixed.__junkKeepAlive())")
print("Mixed == copy: \(mixed == Mixed(id: 1))")
_ = Model()
_ = Worker()
