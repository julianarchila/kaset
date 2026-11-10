import SwiftUI

/// Bottom area of the sidebar: the profile section.
struct SidebarFooterView: View {
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.3)

            SidebarProfileView()
        }
    }
}

#Preview {
    SidebarFooterView()
        .frame(width: 220)
}
