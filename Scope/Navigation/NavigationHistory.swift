import Foundation

struct NavigationLocation: Equatable { let fileURL: URL; let sourceOffset: Int }
final class NavigationHistory {
    private var locations = [NavigationLocation](); private var cursor = -1
    var canGoBack: Bool { cursor > 0 }; var canGoForward: Bool { cursor >= 0 && cursor + 1 < locations.count }
    func record(_ location: NavigationLocation) { if cursor + 1 < locations.count { locations.removeSubrange((cursor + 1)..<locations.count) }; locations.append(location); cursor = locations.count - 1 }
    func back() -> NavigationLocation? { guard canGoBack else { return nil }; cursor -= 1; return locations[cursor] }
    func forward() -> NavigationLocation? { guard canGoForward else { return nil }; cursor += 1; return locations[cursor] }
}
