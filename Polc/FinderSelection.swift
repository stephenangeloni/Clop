import AppKit

enum FinderSelection {
    enum Failure: Error {
        case notAllowed
        case scriptFailed(String)
    }

    static let bundleID = "com.apple.finder"
    private static let notPermitted = -1743

    @MainActor static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    @MainActor static func files() throws -> [URL] {
        let source = """
        tell application id "\(bundleID)"
            set paths to {}
            repeat with selectedItem in (selection as alias list)
                set end of paths to POSIX path of selectedItem
            end repeat
            return paths
        end tell
        """
        var errorInfo: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo) else {
            if errorInfo?[NSAppleScript.errorNumber] as? Int == notPermitted {
                throw Failure.notAllowed
            }
            throw Failure.scriptFailed(errorInfo?[NSAppleScript.errorMessage] as? String ?? "unknown AppleScript error")
        }
        guard result.numberOfItems > 0 else { return [] }
        return (1 ... result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }.map { URL(fileURLWithPath: $0) }
    }
}
