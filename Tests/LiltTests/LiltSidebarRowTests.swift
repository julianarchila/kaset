import SwiftUI
import Testing
@testable import Lilt

@MainActor
@Suite(.tags(.model))
struct LiltSidebarRowTests {
    @Test("LiltSidebarRow constructs selected and unselected rows")
    func constructsSelectedAndUnselectedRows() {
        let selected = LiltSidebarRow(
            title: "Home",
            systemImage: "house",
            isSelected: true,
            action: {}
        )
        let unselected = LiltSidebarRow(
            title: "Search",
            systemImage: "magnifyingglass",
            isSelected: false,
            action: {}
        )

        #expect(String(describing: selected).isEmpty == false)
        #expect(String(describing: unselected).isEmpty == false)
    }
}
