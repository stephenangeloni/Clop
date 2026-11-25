import AppKit
import Defaults
import Lowtech
import SwiftUI

// MARK: - MCPSettingsView

/// Polc's MCP server, and which agents it is installed into. The server is bundled; installing writes
/// one entry into an agent's own config file.
///
/// Same job as rcmd's `AgentsPane` and Crank's `MCPSettingsPane`, built out of Polc's own Form rows
/// rather than their custom controls. Keep the behaviour in step, not the markup.
struct MCPSettingsView: View {
    var body: some View {
        Form {
            Section(header: SectionHeader(title: "MCP")) {
                Toggle(isOn: $mcpEnabled) {
                    Text("Enable MCP").regular(TextSize.body)
                        + Text("\nAllow agents to control Polc, run file optimisations, change settings, write pipelines").round(TextSize.subheadline, weight: .regular).foregroundColor(.secondary)
                }
                .onChange(of: mcpEnabled) { _ in MCPInstaller.writeServerCard() }
                .searchAnchor("mcp.main.mcpEnabled", namesControl: true)

                Toggle(isOn: $mcpAllowScriptSteps) {
                    Text("Allow agents to write arbitrary scripts in pipelines").regular(TextSize.body)
                        + Text("\nUsing scripts in pipelines allows for flexible operations but can be dangerous if not properly verified").round(TextSize.subheadline, weight: .regular).foregroundColor(.secondary)
                }
                .disabled(!mcpEnabled)
                .onChange(of: mcpAllowScriptSteps) { on in
                    guard on else { return }
                    if !askAboutScripts() {
                        mcpAllowScriptSteps = false
                    }
                }
                .searchAnchor("mcp.main.mcpAllowScriptSteps", namesControl: true)
            }

            Section(header: SectionHeader(title: "Install in")) {
                clientRows(MCPInstaller.featuredClients)
                DisclosureGroup(isExpanded: $showMoreClients) {
                    clientRows(MCPInstaller.moreClients)
                } label: {
                    Text("See more").regular(TextSize.body)
                }
            }

            Section(header: SectionHeader(title: "Install by hand")) {
                VStack(alignment: .leading, spacing: Space.l) {
                    CopyableValueRow(title: "Command line", value: MCPInstaller.cliCommand)
                    CopyableValueRow(title: "Server", value: MCPInstaller.cliPath + " " + MCPInstaller.serveArgs.joined(separator: " "))
                }
                .padding(.vertical, Space.xs)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    @State private var states: [String: MCPInstaller.ConfigState] = [:]
    @State private var failures: [String: String] = [:]
    @State private var showMoreClients = false

    @Default(.mcpEnabled) private var mcpEnabled
    @Default(.mcpAllowScriptSteps) private var mcpAllowScriptSteps

    private func clientRows(_ clients: [MCPInstaller.Client]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(clients) { client in
                clientRow(client)
            }
        }
        .padding(.vertical, Space.xs)
    }

    private func clientRow(_ client: MCPInstaller.Client) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(client.name).medium(TextSize.body)
                Text(rowDetail(client))
                    .round(TextSize.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            switch states[client.id] ?? .notInstalled {
            case .installed:
                Button("Remove") { apply(MCPInstaller.remove(client), to: client) }
                    .tint(.red)
            case .unusable:
                // Not a disabled Install: there is no members list to write into, so the only move left
                // is to open the file.
                Button("Show file") { MCPInstaller.revealConfig(client) }
            case .notInstalled:
                Button("Install") { apply(MCPInstaller.install(client), to: client) }
            }
        }
    }

    private func apply(_ result: Result<Void, Error>, to client: MCPInstaller.Client) {
        if case let .failure(error) = result {
            failures[client.id] = error.localizedDescription
        } else {
            // A later success has to clear the earlier failure, or the row keeps showing an error it no
            // longer has.
            failures[client.id] = nil
        }
        refresh()
    }

    private func rowDetail(_ client: MCPInstaller.Client) -> String {
        if let failure = failures[client.id] {
            return failure
        }
        switch states[client.id] ?? .notInstalled {
        case .unusable:
            return "\(client.path) is not a JSON object."
        case .installed, .notInstalled:
            // Once it is added, the useful detail is where it landed.
            return client.isPresent || states[client.id] == .installed
                ? client.path
                : "Not installed on this Mac."
        }
    }

    private func refresh() {
        states = Dictionary(uniqueKeysWithValues: MCPInstaller.clients.map { ($0.id, MCPInstaller.state($0)) })
    }

    private func askAboutScripts() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Allow agents to write scripts?"
        alert.informativeText = """
        A script step runs arbitrary code inside a pipeline.

        Without human verification, it can result in irretrievable file losses as scripts are not sandboxed in any way.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - CopyableValueRow

/// A row whose value is the copy control: click the pill to copy it.
private struct CopyableValueRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).medium(TextSize.body)
            CopyablePill(value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - CopyablePill

private struct CopyablePill: View {
    let value: String

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = true
            mainAsyncAfter(ms: 1200) { copied = false }
        } label: {
            HStack(spacing: Space.xs) {
                // `SwiftUI.Image` qualified: Polc has its own `Image` type for optimisable files.
                SwiftUI.Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: TextSize.micro, weight: .semibold))
                    // Fixed footprint so the glyph swap can't reflow the pill.
                    .frame(width: 12, height: 12)
                Text(copied ? "Copied!" : value)
                    .font(.system(size: TextSize.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.xxs)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Copies the line")
    }

    @State private var copied = false
}
