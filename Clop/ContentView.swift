//
//  ContentView.swift
//  Clop
//
//  Created by Alin Panaitiu on 16.07.2022.
//

import Defaults
import LaunchAtLogin
import Lowtech
import SwiftUI
import System

// MARK: - MenuView

struct MenuView: View {
    @ObservedObject var om = OM
    @ObservedObject var lastApp = LastFocusedAppTracker.shared
    @Environment(\.openWindow) var openWindow

    @Default(.keyComboModifiers) var keyComboModifiers
    @Default(.enabledKeys) var enabledKeys
    @Default(.useAggressiveOptimisationGIF) var useAggressiveOptimisationGIF
    @Default(.useAggressiveOptimisationJPEG) var useAggressiveOptimisationJPEG
    @Default(.useAggressiveOptimisationPNG) var useAggressiveOptimisationPNG
    @Default(.videoEncoder) var videoEncoder
    @Default(.cliInstalled) var cliInstalled
    @Default(.pauseAutomaticOptimisations) var pauseAutomaticOptimisations
    @Default(.allowClopToAppearInScreenshots) var allowClopToAppearInScreenshots
    @Default(.clipboardIgnoredAppBundleIds) var clipboardIgnoredAppBundleIds

    @State var cliInstallResult: String?

    var body: some View {
        Button("Settings") {
            openWindow(id: "settings")
            focus()
        }.keyboardShortcut(",")
        Button("Batch optimiser") {
            BAT.presentForDropping()
        }
        LaunchAtLogin.Toggle()

        Divider()

        Section("Clipboard actions") {
            Button("Optimise") {
                Task { try? await optimiseLastClipboardItem() }
            }.hotkeyHint(.c, "c", enabled: enabledKeys, modifiers: keyComboModifiers.eventModifiers)

            if !useAggressiveOptimisationGIF ||
                !useAggressiveOptimisationJPEG ||
                !useAggressiveOptimisationPNG ||
                videoEncoder != .slowHighQuality
            {
                Button("Optimise (aggressive)") {
                    Task { try? await optimiseLastClipboardItem(aggressiveOptimisation: true) }
                }.hotkeyHint(.a, "a", enabled: enabledKeys, modifiers: keyComboModifiers.eventModifiers)
            }

            Button("Downscale") {
                scalingFactor = max(scalingFactor > 0.5 ? scalingFactor - 0.25 : scalingFactor - 0.1, 0.1)
                Task { try? await optimiseLastClipboardItem(downscaleTo: scalingFactor) }
            }.hotkeyHint(.minus, "-", enabled: enabledKeys, modifiers: keyComboModifiers.eventModifiers)
            Button("Quicklook") {
                Task { try? await quickLookLastClipboardItem() }
            }.hotkeyHint(.space, " ", enabled: enabledKeys, modifiers: keyComboModifiers.eventModifiers)

            if let bundleID = lastApp.bundleId {
                let appName = lastApp.name ?? bundleID
                Toggle("Ignore clipboard events from \(appName)", isOn: Binding(
                    get: { clipboardIgnoredAppBundleIds.contains(bundleID) },
                    set: { ignore in
                        if ignore {
                            clipboardIgnoredAppBundleIds.insert(bundleID)
                        } else {
                            clipboardIgnoredAppBundleIds.remove(bundleID)
                        }
                    }
                ))
            }
        }

        Section("Backups") {
            Button("Open backups folder") {
                NSWorkspace.shared.open(FilePath.clopBackups.url)
            }
            Button("Open working directory") {
                NSWorkspace.shared.open(FilePath.workdir.url)
            }
            Button("Force clean working directory") {
                do {
                    for dir in [FilePath.clopBackups, .videos, .images, .pdfs, .conversions, .downloads, .forResize, .forFilters, .finderQuickAction, .processLogs] {
                        try FileManager.default.removeItem(at: dir.url)
                    }
                } catch {
                    showNotice("Failed to clean working directory\n\(error.localizedDescription)")
                }

                FilePath.workdir.mkdir(withIntermediateDirectories: true, permissions: 0o755)
                guard FilePath.workdir.exists else {
                    showNotice("Failed to create working directory")
                    return
                }

                showNotice("Working directory cleaned")
            }

            Button("Revert last optimisations") {
                om.clipboardImageOptimiser?.restoreOriginal()
            }
            .hotkeyHint(.z, "z", enabled: enabledKeys, modifiers: keyComboModifiers.eventModifiers)
            .disabled(om.clipboardImageOptimiser?.isOriginal ?? true)
            Button("Bring back last result") {
                guard let last = om.removedOptimisers.popLast() else {
                    return
                }
                om.optimisers = om.optimisers.without(last).with(last)
            }
            .hotkeyHint(.equal, "=", enabled: enabledKeys, modifiers: keyComboModifiers.eventModifiers)
            .disabled(om.removedOptimisers.isEmpty)
        }

        Section("Automation") {
            Toggle("Pause automatic optimisations", isOn: $pauseAutomaticOptimisations)
                .searchAnchor("general.main.pauseAutomaticOptimisations")
            if !cliInstalled {
                Button("Install command-line integration") {
                    do {
                        try installCLIBinary()
                        cliInstallResult = "CLI installed at \(CLOP_CLI_BIN_SHELL)"
                    } catch let error as InstallCLIError {
                        cliInstallResult = error.message
                    } catch {
                        cliInstallResult = "Installation failed"
                    }
                    showNotice(cliInstallResult!)
                }
            }
            if let cliInstallResult {
                Text(cliInstallResult).disabled(true)
            } else if cliInstalled {
                Text("CLI installed at \(CLOP_CLI_BIN_SHELL)").disabled(true)
            }
        }

        Menu("About...") {
            Button("Create debug dump") {
                DebugDump.confirmAndRun()
            }
            Text("Version: v\(Bundle.main.version)")
        }

        Toggle("Show Clop UI in screenshots", isOn: $allowClopToAppearInScreenshots)
            .searchAnchor("general.main.allowClopToAppearInScreenshots")
        Divider()
        Button("Quit") {
            NSApp.terminate(nil)
        }.keyboardShortcut("q")
    }
}

extension View {
    /// Attach a menu item's keyboard-shortcut hint only when the matching global hotkey is still
    /// enabled in settings, so disabling a hotkey also drops its (now non-functional) hint from the
    /// menubar menu.
    @ViewBuilder
    func hotkeyHint(_ key: SauceKey, _ equivalent: KeyEquivalent, enabled: [SauceKey], modifiers: EventModifiers) -> some View {
        if enabled.contains(key) {
            keyboardShortcut(equivalent, modifiers: modifiers)
        } else {
            self
        }
    }
}
