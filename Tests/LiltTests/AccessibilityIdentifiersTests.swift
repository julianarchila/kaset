import Testing
@testable import Lilt

@Suite("Accessibility identifiers")
struct AccessibilityIdentifiersTests {
    @Test("Player window identifiers are auxiliary")
    func playerWindowIdentifiersAreAuxiliary() {
        #expect(AccessibilityID.isAuxiliaryPlayerWindowIdentifier(AccessibilityID.VideoWindow.container))
        #expect(AccessibilityID.isAuxiliaryPlayerWindowIdentifier(AccessibilityID.MiniPlayer.container))
    }

    @Test("Missing and unrelated identifiers are not auxiliary")
    func missingAndUnrelatedIdentifiersAreNotAuxiliary() {
        #expect(!AccessibilityID.isAuxiliaryPlayerWindowIdentifier(nil))
        #expect(!AccessibilityID.isAuxiliaryPlayerWindowIdentifier(""))
        #expect(!AccessibilityID.isAuxiliaryPlayerWindowIdentifier("unrelated.window"))
    }
}
