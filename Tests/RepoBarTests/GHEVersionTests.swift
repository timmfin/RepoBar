import Foundation
@testable import RepoBarCore
import Testing

struct GHEVersionTests {
    @Test
    func parsesMajorMinorPatch() {
        let version = GHEVersion(string: "3.12.17")
        #expect(version?.major == 3)
        #expect(version?.minor == 12)
        #expect(version?.patch == 17)
    }

    @Test
    func parsesMajorMinorOnly() {
        let version = GHEVersion(string: "3.15")
        #expect(version?.major == 3)
        #expect(version?.minor == 15)
        #expect(version?.patch == 0)
    }

    @Test
    func returnsNilForInvalidInput() {
        #expect(GHEVersion(string: "invalid") == nil)
        #expect(GHEVersion(string: "3") == nil)
        #expect(GHEVersion(string: "") == nil)
        #expect(GHEVersion(string: "abc.def") == nil)
    }

    @Test
    func comparesVersionsCorrectly() {
        let v312 = GHEVersion(major: 3, minor: 12)
        let v31217 = GHEVersion(major: 3, minor: 12, patch: 17)
        let v315 = GHEVersion(major: 3, minor: 15)
        let v400 = GHEVersion(major: 4, minor: 0)

        #expect(v312 < v315)
        #expect(v312 < v31217)
        #expect(v31217 < v315)
        #expect(v315 < v400)
        #expect(v315 >= GHEVersion(major: 3, minor: 15))
        #expect(v315 == GHEVersion(major: 3, minor: 15, patch: 0))
    }

    @Test
    func pkceThresholdComparison() {
        let pkceMinVersion = GHEVersion(major: 3, minor: 15)

        #expect(GHEVersion(major: 3, minor: 12) < pkceMinVersion)
        #expect(GHEVersion(major: 3, minor: 14) < pkceMinVersion)
        #expect(GHEVersion(major: 3, minor: 15) >= pkceMinVersion)
        #expect(GHEVersion(major: 3, minor: 16) >= pkceMinVersion)
        #expect(GHEVersion(major: 4, minor: 0) >= pkceMinVersion)
    }
}
