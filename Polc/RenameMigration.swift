import AppKit
import Defaults
import Foundation
import Lowtech
import os
import System

private let log = Logger(subsystem: LOG_SUBSYSTEM, category: "RenameMigration")

enum RenameMigration {
    static let formerBundleID = "com.stephenangeloni.Clop"
    static let formerServerName = "clop"

    static func beforeLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: settingsCopiedKey), !formerAppIsRunning else { return }

        for (key, value) in defaults.persistentDomain(forName: formerBundleID) ?? [:] {
            let key = renamedSettingKeys[key] ?? key
            if defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        if let workdir = defaults.string(forKey: "workdir"), standardised(workdir) == formerCaches.path {
            defaults.removeObject(forKey: "workdir")
        }

        do {
            try FolderMerge.move(formerCaches, into: library.appendingPathComponent("Caches/Polc"))
            try FolderMerge.move(library.appendingPathComponent("Application Support/Clop"), into: library.appendingPathComponent("Application Support/Polc"))
        } catch {
            log.error("Could not move Clop's files to Polc, will retry on next launch: \(error, privacy: .public)")
            return
        }
        defaults.set(true, forKey: settingsCopiedKey)
    }

    static func afterLaunch() {
        guard !formerAppIsRunning else { return }
        renameIgnoreFiles()
        repointFormerCommand()
        moveMCPEntries()
        removeFormerServerCard()
    }

    private static let settingsCopiedKey = "settingsCopiedFromClop"
    private static let renamedSettingKeys = ["allowClopToAppearInScreenshots": "allowPolcToAppearInScreenshots"]
    private static let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
    private static let formerCaches = library.appendingPathComponent("Caches/Clop", isDirectory: true)
    private static let formerCommandLink = "\(CLI_BIN_DIR)/clop"

    private static var formerAppIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: formerBundleID).isEmpty
    }

    private static func standardised(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    private static func renameIgnoreFiles() {
        let dirs = [Defaults.Keys.imageDirs, .videoDirs, .pdfDirs, .audioDirs].flatMap { Defaults[$0] }.compactMap(\.existingFilePath)
        for dir in Set(dirs) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.string)) ?? []
            for name in names where name.hasPrefix(".clopignore") {
                let renamed = dir / name.replacingOccurrences(of: ".clopignore", with: ".polcignore")
                if !renamed.exists {
                    _ = try? (dir / name).move(to: renamed)
                }
            }
        }
    }

    private static func repointFormerCommand() {
        let fm = FileManager.default
        guard let destination = try? fm.destinationOfSymbolicLink(atPath: formerCommandLink),
              destination != POLC_CLI_BIN, destination.contains("/Clop.app/")
        else { return }

        do {
            try fm.removeItem(atPath: formerCommandLink)
            try fm.createSymbolicLink(atPath: formerCommandLink, withDestinationPath: POLC_CLI_BIN)
            if !cliSymlinkValid() {
                try installCLIBinary()
            }
        } catch {
            log.error("Could not move the clop command to Polc: \(error, privacy: .public)")
        }
        Defaults[.cliInstalled] = cliSymlinkValid()
    }

    private static func moveMCPEntries() {
        guard MCPInstaller.scriptExists else { return }
        for client in MCPInstaller.clients {
            guard let former = MCPInstaller.installedCommand(client, named: formerServerName),
                  pointsAtFormerApp(former.command)
            else { continue }

            let installed: Result<Void, Error> = MCPInstaller.installedCommand(client) == nil ? MCPInstaller.install(client) : .success(())
            switch installed.flatMap({ MCPInstaller.remove(client, named: formerServerName) }) {
            case .success:
                log.info("Moved the clop MCP entry in \(client.name, privacy: .public) to polc")
            case let .failure(error):
                log.error("Could not move the clop MCP entry in \(client.name, privacy: .public) to polc, will retry on next launch: \(error, privacy: .public)")
            }
        }
    }

    private static func pointsAtFormerApp(_ command: String) -> Bool {
        command.contains("/Clop.app/") || command == formerCommandLink || command.hasSuffix("/.local/bin/clop")
    }

    private static func removeFormerServerCard() {
        let card = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".well-known/mcp/clop.json")
        guard let data = try? Data(contentsOf: card),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["app"] as? [String: Any])?["bundleID"] as? String == formerBundleID
        else { return }
        try? FileManager.default.removeItem(at: card)
    }
}
