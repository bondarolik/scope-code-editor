import SwiftUI

enum SidebarPosition: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct ScopeSettingsView: View {
    @AppStorage("sidebarPosition") private var sidebarPosition = SidebarPosition.left.rawValue

    var body: some View {
        Form {
            Section("Project Sidebar") {
                Picker("Position", selection: $sidebarPosition) {
                    ForEach(SidebarPosition.allCases) { position in
                        Text(position.title).tag(position.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
