import Foundation

struct SymbolEntry: Identifiable, Hashable { let name: String; let kind: String; let fileURL: URL; let relativePath: String; let line: Int; var id: String { "\\(fileURL.path):\\(line):\\(name):\\(kind)" } }
struct SymbolIndex { let entries: [SymbolEntry]; static let empty = SymbolIndex(entries: []); func lookup(_ name: String) -> [SymbolEntry] { entries.filter { $0.name == name } } }
enum CtagsRunner {
    static func buildIndex(rootURL: URL) -> SymbolIndex {
        guard let helper = Bundle.main.url(forResource: "ctags", withExtension: nil, subdirectory: "Tools"), validate(helper) else { return .empty }
        let process = Process(); let output = Pipe(); let errors = Pipe()
        process.executableURL = helper; process.currentDirectoryURL = rootURL; process.standardOutput = output; process.standardError = errors
        process.arguments = ["--output-format=json", "--fields=+nK", "--languages=Ruby", "--recurse=yes", "--exclude=.git", "--exclude=node_modules", "--exclude=vendor/bundle", "--exclude=tmp", "--exclude=log", "--exclude=.bundle", "--exclude=coverage", "--exclude=storage", "--exclude=public/assets", "--exclude=public/packs", "."]
        do { try process.run(); process.waitUntilExit() } catch { return .empty }
        guard process.terminationStatus == 0, let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return .empty }
        let acceptedKinds: Set<String> = ["class", "module", "method", "singletonMethod", "constant"]
        let entries = text.split(separator: "\n").compactMap { line -> SymbolEntry? in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], object["_type"] as? String == "tag", let name = object["name"] as? String, let kind = object["kindName"] as? String, acceptedKinds.contains(kind), let path = object["path"] as? String, let number = object["line"] as? Int else { return nil }
            let url = rootURL.appendingPathComponent(path).standardizedFileURL
            return SymbolEntry(name: name, kind: kind, fileURL: url, relativePath: path, line: number)
        }
        return SymbolIndex(entries: entries)
    }
    private static func validate(_ helper: URL) -> Bool {
        let process = Process(); let pipe = Pipe(); process.executableURL = helper; process.arguments = ["--list-output-formats"]; process.standardOutput = pipe
        do { try process.run(); process.waitUntilExit() } catch { return false }
        let formats = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return process.terminationStatus == 0 && formats.split(separator: "\n").contains { $0.hasPrefix("json") && $0.contains("yes") }
    }
}
