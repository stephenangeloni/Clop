import Foundation

enum FolderMerge {
    static func move(_ source: URL, into destination: URL) throws {
        let fm = FileManager.default
        guard exists(source) else { return }
        guard exists(destination) else {
            try fm.moveItem(at: source, to: destination)
            return
        }

        for name in try fm.contentsOfDirectory(atPath: source.path) {
            let from = source.appendingPathComponent(name)
            let to = destination.appendingPathComponent(name)
            if isDirectory(from), isDirectory(to) {
                try move(from, into: to)
            } else if !exists(to) {
                try fm.moveItem(at: from, to: to)
            }
        }
        if try fm.contentsOfDirectory(atPath: source.path).isEmpty {
            try fm.removeItem(at: source)
        }
    }

    private static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeDirectory
    }
}
