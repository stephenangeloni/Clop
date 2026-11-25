//
//  ContentView.swift
//  Polc
//
//  Created by Alin Panaitiu on 16.07.2022.
//

import Defaults
import Lowtech
import SwiftUI
import System

// MARK: - MenuView

struct MenuView: View {
    @ObservedObject var om = OM
    @ObservedObject var lastApp = LastFocusedAppTracker.shared
    @Environment(\.openWindow) var openWindow

    @Default(.keyComboModifiers) var keyComboModifiers
    @Default(.actionKeys) var actionKeys
    @Default(.useAggressiveOptimisationGIF) var useAggressiveOptimisationGIF
    @Default(.useAggressiveOptimisationJPEG) var useAggressiveOptimisationJPEG
    @Default(.useAggressiveOptimisationPNG) var useAggressiveOptimisationPNG
    @Default(.videoEncoder) var videoEncoder
    @Default(.cliInstalled) var cliInstalled
    @Default(.pauseAutomaticOptimisations) var pauseAutomaticOptimisations
    @Default(.allowPolcToAppearInScreenshots) var allowPolcToAppearInScreenshots
    @Default(.clipboardIgnoredAppBundleIds) var clipboardIgnoredAppBundleIds

    @State var cliInstallResult: String?

    var body: some View {
        Section("Clipboard") {
            Button("Optimise") {
                Task { try? await optimiseLastClipboardItem() }
            }.hotkeyHint(.optimiseClipboard, in: actionKeys, modifiers: keyComboModifiers)

            if !useAggressiveOptimisationGIF ||
                !useAggressiveOptimisationJPEG ||
                !useAggressiveOptimisationPNG ||
                videoEncoder != .slowHighQuality
            {
                Button("Optimise (aggressive)") {
                    Task { try? await optimiseLastClipboardItem(aggressiveOptimisation: true) }
                }.hotkeyHint(.optimiseAggressively, in: actionKeys, modifiers: keyComboModifiers)
            }

            Button("Downscale") {
                scalingFactor = max(scalingFactor > 0.5 ? scalingFactor - 0.25 : scalingFactor - 0.1, 0.1)
                Task { try? await optimiseLastClipboardItem(downscaleTo: scalingFactor) }
            }.hotkeyHint(.downscale, in: actionKeys, modifiers: keyComboModifiers)
            Button("Quick Look") {
                Task { try? await quickLookLastClipboardItem() }
            }.hotkeyHint(.quickLook, in: actionKeys, modifiers: keyComboModifiers)
            Button("Revert last optimisation") {
                om.clipboardImageOptimiser?.restoreOriginal()
            }
            .hotkeyHint(.restoreOriginal, in: actionKeys, modifiers: keyComboModifiers)
            .disabled(om.clipboardImageOptimiser?.isOriginal ?? true)
            Button("Bring back last result") {
                guard let last = om.removedOptimisers.popLast() else {
                    return
                }
                om.optimisers = om.optimisers.without(last).with(last)
            }
            .hotkeyHint(.bringBack, in: actionKeys, modifiers: keyComboModifiers)
            .disabled(om.removedOptimisers.isEmpty)

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

        Divider()

        Toggle("Pause automatic optimisations", isOn: $pauseAutomaticOptimisations)
            .searchAnchor("general.main.pauseAutomaticOptimisations")
        Button("Batch optimiser…") {
            BAT.presentForDropping()
        }

        Divider()

        Button("Settings…") {
            openWindow(id: "settings")
            focus()
        }.keyboardShortcut(",")
        Menu("Advanced") {
            Button("Open backups folder") {
                NSWorkspace.shared.open(FilePath.polcBackups.url)
            }
            Button("Open working directory") {
                NSWorkspace.shared.open(FilePath.workdir.url)
            }
            Button("Force clean working directory") {
                forceCleanWorkingDirectory()
            }

            Divider()

            if cliInstalled {
                Text("CLI installed at \(POLC_CLI_BIN_SHELL)").disabled(true)
            } else {
                Button("Install command-line integration") {
                    installCommandLineIntegration()
                }
                if let cliInstallResult {
                    Text(cliInstallResult).disabled(true)
                }
            }
            Toggle("Show Polc UI in screenshots", isOn: $allowPolcToAppearInScreenshots)
                .searchAnchor("general.main.allowPolcToAppearInScreenshots")
            Button("Create debug dump…") {
                DebugDump.confirmAndRun()
            }
        }

        Divider()

        Text("Polc \(Bundle.main.version)").disabled(true)
        Button("Quit Polc") {
            NSApp.terminate(nil)
        }.keyboardShortcut("q")
    }

    func forceCleanWorkingDirectory() {
        do {
            for dir in [FilePath.polcBackups, .videos, .images, .pdfs, .conversions, .downloads, .forResize, .forFilters, .finderQuickAction, .processLogs] {
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

    func installCommandLineIntegration() {
        do {
            try installCLIBinary()
            cliInstallResult = "CLI installed at \(POLC_CLI_BIN_SHELL)"
        } catch let error as InstallCLIError {
            cliInstallResult = error.message
        } catch {
            cliInstallResult = "Installation failed"
        }
        showNotice(cliInstallResult!)
    }
}

extension View {
    /// Attach a menu item's keyboard-shortcut hint only when the matching global hotkey is still
    /// enabled in settings, so disabling a hotkey also drops its (now non-functional) hint from the
    /// menubar menu.
    @ViewBuilder
    func hotkeyHint(_ action: GlobalAction, in actionKeys: [GlobalAction: ActionKey<SauceKey>], modifiers: [TriggerKey]) -> some View {
        if let actionKey = actionKeys.complete[action], actionKey.enabled, let equivalent = actionKey.key.keyEquivalent(heldWith: modifiers) {
            keyboardShortcut(equivalent, modifiers: modifiers.eventModifiers)
        } else {
            self
        }
    }
}
