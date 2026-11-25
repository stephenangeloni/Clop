import Foundation

enum FolderMerge {
    static func move(_ source: URL, into destination: URL) throws {
        let fm = FileManager.default
        guard try exists(source) else { return }
        guard try exists(destination) else {
            try fm.moveItem(at: source, to: destination)
            return
        }

        for name in try fm.contentsOfDirectory(atPath: source.path) {
            let from = source.appendingPathComponent(name)
            let to = destination.appendingPathComponent(name)
            if try isDirectory(from), try isDirectory(to) {
                try move(from, into: to)
            } else if try !exists(to) {
                try fm.moveItem(at: from, to: to)
            }
        }
        if try fm.contentsOfDirectory(atPath: source.path).isEmpty {
            try fm.removeItem(at: source)
        }
    }

    private static func exists(_ url: URL) throws -> Bool {
        try attributes(url) != nil
    }

    private static func isDirectory(_ url: URL) throws -> Bool {
        try attributes(url)?[.type] as? FileAttributeType == .typeDirectory
    }

    private static func attributes(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            return nil
        }
    }
}
