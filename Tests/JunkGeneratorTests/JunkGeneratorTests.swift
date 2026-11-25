import JunkGenerator
import XCTest

final class JunkGeneratorTests: XCTestCase {
    func testSameConfigurationGivesSameSource() {
        let config = JunkConfiguration(
            stored: 20, kinds: JunkKind.allCases, computed: 5, methods: 5, keepAlive: true, seed: 7
        )
        XCTAssertEqual(JunkGenerator.members(for: config), JunkGenerator.members(for: config))
    }

    func testSeedChangesValues() {
        let a = JunkGenerator.members(for: JunkConfiguration(stored: 4, methods: 2, seed: 1))
        let b = JunkGenerator.members(for: JunkConfiguration(stored: 4, methods: 2, seed: 2))
        XCTAssertNotEqual(a, b)
    }

    func testDefaultSeedIsStable() {
        // FNV-1a of "Foo". A change here would silently change every expansion.
        XCTAssertEqual(JunkGenerator.defaultSeed(for: "Foo"), 0xf2bb_9519_9c92_e1d7)
        XCTAssertNotEqual(JunkGenerator.defaultSeed(for: "Foo"), JunkGenerator.defaultSeed(for: "Bar"))
    }

    func testMemberCountsAndNames() {
        let config = JunkConfiguration(stored: 3, computed: 2, methods: 1, keepAlive: true, seed: 0)
        let members = JunkGenerator.members(for: config)
        XCTAssertEqual(members.count, 7)
        XCTAssertEqual(
            JunkGenerator.memberNames(for: config),
            ["__junk_s0", "__junk_s1", "__junk_s2", "__junk_c0", "__junk_c1", "__junk_m0", "__junkKeepAlive"]
        )
        for (member, name) in zip(members, JunkGenerator.memberNames(for: config)) {
            XCTAssertTrue(member.contains(name), "\(member) should declare \(name)")
        }
    }

    func testKindsAreAppliedRoundRobin() {
        let config = JunkConfiguration(stored: 5, kinds: [.int, .string], seed: 0)
        let types = JunkGenerator.members(for: config).map { member in
            member.split(separator: " ")[2]
        }
        XCTAssertEqual(types, ["Int", "String", "Int", "String", "Int"])
    }

    func testAddingMethodsDoesNotChangeStoredValues() {
        let base = JunkGenerator.members(for: JunkConfiguration(stored: 4, seed: 9))
        let more = JunkGenerator.members(for: JunkConfiguration(stored: 4, methods: 3, seed: 9))
        XCTAssertEqual(Array(more.prefix(4)), base)
    }

    func testStringsAreAboveSmallStringLimit() throws {
        let member = try XCTUnwrap(
            JunkGenerator.members(for: JunkConfiguration(stored: 1, kinds: [.string], seed: 3)).first
        )
        let literal = try XCTUnwrap(member.split(separator: "\"").dropFirst().first)
        XCTAssertGreaterThan(literal.utf8.count, 15)
    }

    func testAccessLevelIsApplied() {
        let members = JunkGenerator.members(
            for: JunkConfiguration(stored: 1, computed: 1, methods: 1, access: .private, keepAlive: true, seed: 0)
        )
        for member in members {
            XCTAssertTrue(member.contains("private "), member)
        }
        let internalMembers = JunkGenerator.members(for: JunkConfiguration(stored: 1, seed: 0))
        XCTAssertTrue(internalMembers[0].hasPrefix("var "))
    }

    func testZeroCountsProduceNothing() {
        XCTAssertEqual(JunkGenerator.members(for: JunkConfiguration(stored: 0, seed: 0)), [])
    }
}
