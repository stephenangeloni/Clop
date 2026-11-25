//
//  SettingsView.swift
//  Polc
//
//  Created by Alin Panaitiu on 10.07.2023.
//

import Defaults
import Foundation
import LaunchAtLogin
import Lowtech
import os
import SwiftUI
import System

private let log = Logger(subsystem: LOG_SUBSYSTEM, category: "SettingsView")

let TEXT_FIELD_OFFSET: CGFloat = if #available(macOS 15.0, *) {
    4
} else {
    0
}
let TEXT_FIELD_SCALE: CGFloat = if #available(macOS 15.0, *) {
    1.1
} else {
    1.0
}
let TEXT_FIELD_WIDTH: CGFloat = 550

extension String: @retroactive Identifiable {
    public var id: String {
        self
    }
}

let NOT_ALLOWED_TO_WATCH = [FilePath.polcBackups, FilePath.images, FilePath.videos, FilePath.forResize, FilePath.conversions, FilePath.downloads].map(\.portablePath)

import Combine

class TextDebounce: ObservableObject {
    init(for time: DispatchQueue.SchedulerTimeType.Stride) {
        $text
            .debounce(for: time, scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, value != debouncedText else {
                    return
                }
                DirListView.shouldSave = true
                debouncedText = value
            }
            .store(in: &subscriptions)
    }

    @Published var debouncedText = ""
    @Published var text = ""

    private var subscriptions = Set<AnyCancellable>()
}

// MARK: - SidebarHue

/// A muted, earthy sidebar colour with a light/dark pair: deeper on the light
/// sidebar, lifted on the dark one so the glyph keeps its weight either way.
/// Skin / stone / ochre / plum tones instead of saturated system
/// colours. File-type tabs use the file-type colours from `Palette` instead.
struct SidebarHue {
    static let dustyBlue = rgb(0.24, 0.43, 0.63, 0.53, 0.64, 0.75)
    static let violet = rgb(0.52, 0.32, 0.75, 0.70, 0.58, 0.88)
    static let orchid = rgb(0.70, 0.25, 0.70, 0.85, 0.55, 0.85)
    static let skin = rgb(0.74, 0.47, 0.30, 0.80, 0.64, 0.52)
    static let plum = rgb(0.58, 0.30, 0.55, 0.68, 0.55, 0.67)
    static let mutedTeal = rgb(0.15, 0.50, 0.45, 0.47, 0.68, 0.63)
    static let stone = rgb(0.45, 0.43, 0.37, 0.66, 0.64, 0.57)
    static let ochre = rgb(0.78, 0.56, 0.16, 0.83, 0.68, 0.40)

    let light: Color
    let dark: Color

    func color(for scheme: ColorScheme) -> Color {
        scheme == .dark ? dark : light
    }

    private static func rgb(_ lr: Double, _ lg: Double, _ lb: Double, _ dr: Double, _ dg: Double, _ db: Double) -> SidebarHue {
        SidebarHue(
            light: Color(.sRGB, red: lr, green: lg, blue: lb),
            dark: Color(.sRGB, red: dr, green: dg, blue: db)
        )
    }

}

// MARK: - SidebarIcon

/// The category glyph as a soft tinted tile: the earthy hue drives both the
/// glyph and a low-opacity same-hue background. `.resizable` into a fixed inner
/// frame keeps every glyph one size with a consistent inset from the tile edge.
struct SidebarIcon: View {
    let symbol: String
    let hue: SidebarHue
    var dimmed = false

    var body: some View {
        let color = hue.color(for: scheme)
        let tileOpacity = (scheme == .dark ? 0.22 : 0.15) * (dimmed ? 0.7 : 1)
        SwiftUI.Image(systemName: symbol)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color.opacity(dimmed ? 0.55 : 1))
            .frame(width: 12, height: 12)
            .frame(width: 20, height: 20)
            .background(
                color.opacity(tileOpacity),
                in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            )
    }

    @Environment(\.colorScheme) private var scheme

}

struct DirListView: View {
    static var shouldSave = false

    var fileType: PolcFileType
    @StateObject var textDebounce = TextDebounce(for: .seconds(2))

    @Binding var dirs: [String]
    @Binding var enabled: Bool
    @State var selectedDirs: Set<String> = []
    @State var chooseFile = false
    @State var polcignoreHelpVisible = false
    @State var automationsExpanded = true

    var hideIgnoreRules = false

    @Default(.dirsHideFloatingResult) var dirsHideFloatingResult

    @ViewBuilder var ignoreRulesView: some View {
        if selectedDirs.count == 1, let dir = selectedDirs.first {
            HStack {
                Text("Ignore rules").semibold(TextSize.callout).fixedSize()
                Spacer()
                Text("\(dir.replacingOccurrences(of: HOME.string, with: "~"))/.polcignore-\(fileType.rawValue)")
                    .mono(TextSize.subheadline)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .frame(maxWidth: 400, alignment: .trailing)
            }.padding(.top, Space.xs).opacity(0.8)
            TextEditor(text: $textDebounce.text)
                .font(.mono(TextSize.callout))
                .onChange(of: textDebounce.debouncedText, perform: { value in
                    guard Self.shouldSave else { return }
                    saveIgnoreRules(text: value)
                })
                .frame(height: 100)
            HStack {
                Text("Follows the standard .gitignore rules.").regular(TextSize.caption)
                Button("\(SwiftUI.Image(systemName: "arrowtriangle.down.square")) Click for more info") {
                    polcignoreHelpVisible.toggle()
                }
                .buttonStyle(.plain)
                .font(.semibold(TextSize.caption))
            }
            .opacity(0.8)

            if polcignoreHelpVisible {
                ScrollView {
                    Text("""
                    **Pattern syntax:**

                    1. **Wildcards**: You can use asterisks (`*`) as wildcards to match multiple characters or directories at any level. For example, `*.jpg` will match all files with the .jpg extension, such as `image.jpg` or `photo.jpg`. Similarly, `*.pdf` will match any PDF files.

                    2. **Directory names**: You can specify directories in patterns by ending the pattern with a slash (/). For instance, `images/` will match all files or directories named "images" or residing within an "images" directory.

                    3. **Negation**: Prefixing a pattern with an exclamation mark (!) negates the pattern, instructing the app to include files that would otherwise be excluded. For example, `!important.pdf` would include a file named "important.pdf" even if it satisfies other exclusion patterns.

                    4. **Comments**: You can include comments by adding a hash symbol (`#`) at the beginning of the line. These comments are ignored by the app and serve as helpful annotations for humans.

                    *More complex patterns can be found in the [gitignore documentation](https://git-scm.com/docs/gitignore#_pattern_format).*

                    **Examples:**

                    `# Ignore all files with the .jpg extension`
                    `*.jpg`
                    ` `
                    `# Ignore all folders and subfolders (like a non-recursive option)`
                    `*/*`
                    ` `
                    `# Exclude all files in a "DontOptimise" directory`
                    `DontOptimise/`
                    ` `
                    `# Exclude all MKV video files`
                    `*.mkv`
                    ` `
                    `# Exclude invoices (PDF files starting with "invoice-")`
                    `invoice-*.pdf`
                    ` `
                    `# Exclude a specific file named "confidential.pdf"`
                    `confidential.pdf`
                    ` `
                    `# Include a specific file named "important.pdf" even if it matches other patterns`
                    `!important.pdf`
                    """)
                    .foregroundColor(.secondary)
                }
                .roundbg(color: .black.opacity(0.05))
            }
        } else {
            (Text("Select a single path to edit its ") + Text("Ignore rules").bold())
                .padding(.top, Space.xs)
                .opacity(0.8)
        }

    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ScrollView {
                Table(dirs.sorted(), selection: $selectedDirs) {
                    TableColumn("Path") { dir in Text(dir.replacingOccurrences(of: HOME.string, with: "~")).mono(TextSize.callout) }
                    TableColumn("Show floating results") { dir in
                        Toggle("Show floating results", isOn: showFloatingBinding(for: dir))
                            .toggleStyle(.checkbox)
                            .controlSize(.mini)
                            .labelsHidden()
                            .help("Show the floating thumbnail and progress when files in this folder are optimised")
                    }
                    .width(130)
                    TableColumn("") { dir in
                        Button(dirHasAutomation(dir) ? "Edit automation" : "Add automation") {
                            showAutomations(folder: dir, addNew: !dirHasAutomation(dir))
                        }
                        .font(.round(TextSize.caption))
                        .buttonStyle(.borderless)
                        .foregroundColor(.accentColor)
                    }
                    .width(110)
                }
                .tableStyle(.inset)
                .frame(height: 150)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.6)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium))
                .searchAnchor("images.watchpaths.dirsHideFloatingResult")
            }.frame(height: 150)

            HStack(spacing: Space.xs) {
                Button(action: { chooseFile = true }, label: { SwiftUI.Image(systemName: "plus").font(.bold(TextSize.callout)).frame(width: 16, height: 16) })
                    .fileImporter(
                        isPresented: $chooseFile,
                        allowedContentTypes: [.directory],
                        allowsMultipleSelection: true,
                        onCompletion: { result in
                            switch result {
                            case let .success(success):
                                dirs = (dirs + success.map(\.path.portablePath)).uniqued.without(NOT_ALLOWED_TO_WATCH)
                            case let .failure(failure):
                                log.error("\(failure.localizedDescription)")
                            }
                        }
                    )
                    .disabled(!enabled)

                Button(
                    action: {
                        dirs = Set(dirs).without(selectedDirs)
                        selectedDirs = []
                    },
                    label: { SwiftUI.Image(systemName: "minus").font(.bold(TextSize.callout)).frame(width: 16, height: 16) }
                )
                .disabled(selectedDirs.isEmpty || !enabled)
                Spacer()
                Toggle(" Enable **\(fileType == .pdf ? "PDF" : fileType.rawValue)** auto-optimiser", isOn: $enabled)
                    .font(.round(TextSize.subheadline, weight: .regular))
                    .controlSize(.mini)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .searchAnchor("pdf.watchpaths.enableAutomaticPDFOptimisations")
                    .searchAnchor("audio.watchpaths.enableAutomaticAudioOptimisations")
                    .searchAnchor("images.watchpaths.enableAutomaticImageOptimisations")
                    .searchAnchor("video.watchpaths.enableAutomaticVideoOptimisations")
            }

            if enabled, selectedDirs.count == 1, let dir = selectedDirs.first {
                FolderAutomationsSection(fileType: fileType, folder: dir, expanded: $automationsExpanded)
            }
            if !hideIgnoreRules, enabled {
                ignoreRulesView
            }
        }
        .padding(Space.xs)
        .onChange(of: selectedDirs) { [selectedDirs] newSelectedDirs in
            Self.shouldSave = false
            guard newSelectedDirs.count == 1, let dir = newSelectedDirs.first else {
                return
            }
            if textDebounce.text != textDebounce.debouncedText {
                saveIgnoreRules(text: textDebounce.text, dir: selectedDirs.first)
            }

            textDebounce.debouncedText = (try? String(contentsOfFile: "\(dir.resolvedPath)/.polcignore-\(fileType.rawValue)")) ?? ""
            textDebounce.text = textDebounce.debouncedText
        }
        .onChange(of: enabled) { enabled in
            if !enabled {
                selectedDirs = []
            }
        }
    }

    func showFloatingBinding(for dir: String) -> Binding<Bool> {
        Binding(
            get: { !dirsHideFloatingResult.contains(dir) },
            set: { show in
                if show {
                    dirsHideFloatingResult.remove(dir)
                } else {
                    dirsHideFloatingResult.insert(dir)
                }
            }
        )
    }

    func dirHasAutomation(_ dir: String) -> Bool {
        Defaults[fileType.pipelineKey][dir]?.isEmpty == false
    }

    func showAutomations(folder: String, addNew: Bool) {
        selectedDirs = [folder]
        withAnimation(.easeOut(duration: 0.15)) { automationsExpanded = true }
        guard addNew else { return }
        var dict = Defaults[fileType.pipelineKey]
        dict[folder, default: []].append(Pipeline(steps: []))
        Defaults[fileType.pipelineKey] = dict
    }

    func saveIgnoreRules(text: String, dir: String? = nil) {
        guard let dir = dir ?? selectedDirs.first else { return }

        let polcIgnore = "\(dir.resolvedPath)/.polcignore-\(fileType.rawValue)"
        guard text.isNotEmpty else {
            log.debug("Deleting \(polcIgnore)")
            try? fm.removeItem(atPath: polcIgnore)
            return
        }
        do {
            log.debug("Saving \(polcIgnore)")
            try text.write(toFile: polcIgnore, atomically: false, encoding: .utf8)
        } catch {
            log.error("\(error.localizedDescription)")
        }
    }
}

/// Per-path automations shown below the watched-paths table. Edits the same Defaults the
/// Automation tab uses (`fileType.pipelineKey`), filtered to a single folder.
struct FolderAutomationsSection: View {
    let fileType: PolcFileType
    let folder: String
    @Binding var expanded: Bool

    @Default(.pipelinesToRunOnImage) var imagePipelines
    @Default(.pipelinesToRunOnVideo) var videoPipelines
    @Default(.pipelinesToRunOnPdf) var pdfPipelines
    @Default(.pipelinesToRunOnAudio) var audioPipelines

    var pipelinesBinding: Binding<[String: [Pipeline]]> {
        switch fileType {
        case .image: $imagePipelines
        case .video: $videoPipelines
        case .pdf: $pdfPipelines
        case .audio: $audioPipelines
        }
    }

    var count: Int {
        pipelinesBinding.wrappedValue[folder]?.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button(action: { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } }) {
                HStack(spacing: Space.xs) {
                    SwiftUI.Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.semibold(TextSize.caption)).foregroundColor(.secondary)
                    Text("Automations").semibold(TextSize.callout)
                    if count > 0 {
                        Text("\(count)").mono(TextSize.caption)
                            .padding(.horizontal, Space.xs).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.1)))
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                PipelineEditorRow(
                    source: .dir(folder),
                    fileType: fileType,
                    pipelines: pipelinesBinding,
                    editingKey: $editingKey,
                    onRemoveSource: { pipelinesBinding.wrappedValue[folder] = nil }
                )
            }
        }
        .padding(.top, Space.xs)
    }

    @State private var editingKey: String?

}

/// Reusable automation editor scoped to a single non-folder `OptimisationSource`
/// (drop zone, clipboard). Stacks one `PipelineEditorRow` per file type, each
/// bound to the matching `pipelinesToRunOn<Type>` Defaults dict keyed by
/// `source.string`. Writes the SAME storage as the Automation tab, so both
/// views update live. Per-file-type editors are always shown (no collapse).
///
/// Produces interface (consumed by the clipboard pane in a later phase):
///   SourceAutomationsSection(source: .dropZone)
struct SourceAutomationsSection: View {
    let source: OptimisationSource
    var disabledTypes: Set<PolcFileType> = []

    @Default(.pipelinesToRunOnImage) var imagePipelines
    @Default(.pipelinesToRunOnVideo) var videoPipelines
    @Default(.pipelinesToRunOnPdf) var pdfPipelines
    @Default(.pipelinesToRunOnAudio) var audioPipelines

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(PolcFileType.allCases, id: \.self) { fileType in
                let isDisabled = disabledTypes.contains(fileType)
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.xs) {
                        SwiftUI.Image(systemName: fileType.symbolName)
                            .frame(width: 14)
                        Text(fileType == .pdf ? "PDF" : fileType.description.capitalized)
                            .semibold(TextSize.caption)
                    }
                    .foregroundColor(fileType.color)
                    PipelineEditorRow(
                        source: source,
                        fileType: fileType,
                        pipelines: binding(for: fileType),
                        editingKey: $editingKey,
                        onRemoveSource: nil,
                        hideInertRemoveButton: true
                    )
                }
                .disabled(isDisabled)
                .saturation(isDisabled ? 0 : 1)
                .opacity(isDisabled ? 0.5 : 1)
            }
        }
        .padding(.top, Space.xs)
    }

    func binding(for fileType: PolcFileType) -> Binding<[String: [Pipeline]]> {
        switch fileType {
        case .image: $imagePipelines
        case .video: $videoPipelines
        case .pdf: $pdfPipelines
        case .audio: $audioPipelines
        }
    }

    @State private var editingKey: String?

}

struct PDFSettingsView: View {
    @Default(.pdfDirs) var pdfDirs
    @Default(.maxPDFSizeMB) var maxPDFSizeMB
    @Default(.minPDFSizeKB) var minPDFSizeKB
    @Default(.maxPDFFileCount) var maxPDFFileCount
    @Default(.pdfDPI) var pdfDPI
    @Default(.enableAutomaticPDFOptimisations) var enableAutomaticPDFOptimisations

    var body: some View {
        Form {
            Section(header: SectionHeader(title: "Watch paths", subtitle: "Optimise PDFs as they appear in these folders")) {
                DirListView(fileType: .pdf, dirs: $pdfDirs, enabled: $enableAutomaticPDFOptimisations)
            }
            .searchAnchor("pdf.watchpaths.pdfDirs")
            Section(header: SectionHeader(title: "Optimisation rules")) {
                HStack(spacing: Space.xs) {
                    SwiftUI.Image(systemName: "folder.badge.gearshape")
                    Text("Where files go is set in").foregroundColor(.secondary)
                    Button("File handling") { settingsViewManager.tab = .files }.buttonStyle(.link)
                }.font(.system(size: TextSize.subheadline))
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.s) {
                        Text("Compression").regular(TextSize.body)
                            .searchAnchor("pdf.optimisationrules.pdfDPI")
                        Slider(
                            value: Binding(
                                get: { Double(pdfStopIndex(pdfDPI == PDF_DPI_ADAPTIVE ? lastPDFDPI : pdfDPI)) },
                                set: { pdfDPI = PDF_DPI_STOPS[Int($0.rounded())] }
                            ),
                            in: 0 ... Double(PDF_DPI_STOPS.count - 1), step: 1
                        )
                        .accessibilityLabel("Compression")
                        .disabled(pdfDPI == PDF_DPI_ADAPTIVE)
                        Text("\(pdfDPI == PDF_DPI_ADAPTIVE ? lastPDFDPI : pdfDPI) DPI")
                            .mono(TextSize.subheadline).foregroundColor(.secondary)
                            .opacity(pdfDPI == PDF_DPI_ADAPTIVE ? 0.2 : 1)
                            .frame(width: 56, alignment: .trailing)
                        Button("Adaptive") {
                            if pdfDPI == PDF_DPI_ADAPTIVE {
                                pdfDPI = lastPDFDPI
                            } else {
                                lastPDFDPI = pdfDPI
                                pdfDPI = PDF_DPI_ADAPTIVE
                            }
                        }
                        .buttonStyle(ToggleButton(isOn: .oneway { pdfDPI == PDF_DPI_ADAPTIVE }))
                        .font(.mono(TextSize.subheadline))
                    }
                    Text(pdfCompressionSubtitle).round(TextSize.caption, weight: .regular).foregroundColor(.secondary)
                }
            }
            Section(header: SectionHeader(title: "Watched file filters", subtitle: "Only files within these limits are optimised")) {
                FileSizeRangeRow(minKB: $minPDFSizeKB, maxMB: $maxPDFSizeMB)
                    .searchAnchor("pdf.watchedfilefilters.minPDFSizeKB")
                CountSliderRow(count: $maxPDFFileCount, caption: { "Skips optimisation when more than \($0) \($0 == 1 ? "PDF is" : "PDFs are") copied or moved at once" })
                    .searchAnchor("pdf.watchedfilefilters.maxPDFFileCount")
            }
        }
        .scrollContentBackground(.hidden)
        .padding(Space.xs)
    }

    @State private var lastPDFDPI = 150

    private var pdfCompressionSubtitle: String {
        if pdfDPI == PDF_DPI_ADAPTIVE {
            return "Polc automatically picks a per-PDF DPI from the source image density and downscales images above it"
        }
        if pdfDPI >= PDF_DPI_NO_DOWNSAMPLE {
            return "Lossless compression, tries to save space on metadata and reencoding. May not yield significant size reductions."
        }
        return "Downscales high resolution images to \(pdfDPI) DPI; lower-resolution images are left untouched"
    }

    private func pdfStopIndex(_ dpi: Int) -> Int {
        PDF_DPI_STOPS.firstIndex(of: dpi)
            ?? PDF_DPI_STOPS.enumerated().min(by: { abs($0.element - dpi) < abs($1.element - dpi) })?.offset
            ?? 0
    }

}

struct VideoSettingsView: View {
    @Default(.videoDirs) var videoDirs
    @Default(.formatsToConvertToMP4) var formatsToConvertToMP4
    @Default(.maxVideoSizeMB) var maxVideoSizeMB
    @Default(.minVideoSizeKB) var minVideoSizeKB
    @Default(.minVideoResolution) var minVideoResolution
    @Default(.maxVideoResolution) var maxVideoResolution
    @Default(.videoFormatsToSkip) var videoFormatsToSkip
    @Default(.adaptiveVideoSize) var adaptiveVideoSize
    @Default(.capVideoFPS) var capVideoFPS
    @Default(.targetVideoFPS) var targetVideoFPS
    @Default(.minVideoFPS) var minVideoFPS
    @Default(.playbackSpeedFrameBehaviour) var playbackSpeedFrameBehaviour
    @Default(.maxVideoFileCount) var maxVideoFileCount
    @Default(.removeAudioFromVideos) var removeAudioFromVideos
    @Default(.convertAudioToAAC) var convertAudioToAAC

    @Default(.videoEncoder) var videoEncoder
    @Default(.videoCompression) var videoCompression
    #if arch(arm64)
        @Default(.useCPUIntensiveEncoder) var useCPUIntensiveEncoder
    #endif
    @Default(.useAggressiveOptimisationMP4) var useAggressiveOptimisationMP4
    @Default(.enableAutomaticVideoOptimisations) var enableAutomaticVideoOptimisations

    var videoResolvedTier: CompressionTier {
        videoCompression.tier == .custom ? .smaller : videoCompression.tier
    }

    var body: some View {
        CompatibilityScrollForm {
            Section(header: SectionHeader(title: "Watch paths", subtitle: "Optimise videos as they appear in these folders")) {
                DirListView(fileType: .video, dirs: $videoDirs, enabled: $enableAutomaticVideoOptimisations)
            }
            .searchAnchor("video.watchpaths.videoDirs")
            Section(header: SectionHeader(title: "Optimisation rules")) {
                HStack(spacing: Space.xs) {
                    SwiftUI.Image(systemName: "folder.badge.gearshape")
                    Text("Where files go is set in").foregroundColor(.secondary)
                    Button("File handling") { settingsViewManager.tab = .files }.buttonStyle(.link)
                }.font(.system(size: TextSize.subheadline))
                HStack(spacing: Space.s) {
                    Text("Compression").regular(TextSize.body)
                        .searchAnchor("video.optimisationrules.videoCompression")
                    Spacer()
                    Menu {
                        ForEach([CompressionTier.adaptive, .lossless, .fast, .smaller], id: \.self) { tier in
                            Toggle(isOn: Binding(
                                get: { videoResolvedTier == tier },
                                set: {
                                    if $0 {
                                        videoCompression = CompressionQuality(tier: tier, factor: videoCompression.factor)
                                    }
                                }
                            )) {
                                Text(videoCompressionTitle(tier))
                                Text(videoCompressionSubtitle(tier))
                            }
                        }
                    } label: {
                        Text(videoCompressionTitle(videoResolvedTier))
                    }
                    .menuStyle(.button)
                    .fixedSize()
                }
                if videoCompression.tier == .smaller || videoCompression.tier == .custom {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.s) {
                            Button("Auto") {
                                if videoCompression.videoUsesAutoCRF {
                                    videoCompression = CompressionQuality(tier: .smaller, factor: lastVideoFactor)
                                } else {
                                    lastVideoFactor = max(5, videoCompression.factor)
                                    videoCompression = CompressionQuality(tier: .smaller, factor: 0)
                                }
                            }
                            .buttonStyle(ToggleButton(isOn: .oneway { videoCompression.videoUsesAutoCRF }))
                            .font(.mono(TextSize.subheadline))
                            Slider(
                                value: Binding(
                                    get: { Double(videoCompression.videoUsesAutoCRF ? lastVideoFactor : max(5, videoCompression.factor)) },
                                    set: { videoCompression = CompressionQuality(tier: .smaller, factor: Int($0.rounded())) }
                                ),
                                in: 5 ... 100, step: 1
                            ) {
                                EmptyView()
                            } minimumValueLabel: {
                                Text("Better quality").round(TextSize.caption, weight: .regular).foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("Smaller size").round(TextSize.caption, weight: .regular).foregroundColor(.secondary)
                            }
                            .accessibilityLabel("Compression")
                            .frame(maxWidth: .infinity)
                            .disabled(videoCompression.videoUsesAutoCRF)
                            .help("Drag toward Better quality for better-looking video, toward Smaller size for a smaller file")
                            Text("\(videoCompression.videoUsesAutoCRF ? lastVideoFactor : videoCompression.factor)%")
                                .mono(TextSize.subheadline).foregroundColor(.secondary)
                                .opacity(videoCompression.videoUsesAutoCRF ? 0.2 : 1)
                                .frame(width: 38, alignment: .trailing)
                        }
                        if videoCompression.videoUsesAutoCRF {
                            Text("The encoder will choose the best compression factor based on the video contents")
                                .round(TextSize.caption, weight: .regular).foregroundColor(.secondary)
                        }
                    }
                }
                Toggle("Remove audio on optimised videos", isOn: $removeAudioFromVideos)
                    .searchAnchor("video.optimisationrules.removeAudioFromVideos", namesControl: true)
                Toggle(isOn: $capVideoFPS.animation(.spring())) {
                    HStack {
                        Text("Cap frames per second to").regular(TextSize.body).padding(.trailing, Space.s)
                        Spacer()

                        Button("30fps") {
                            withAnimation(.spring()) { targetVideoFPS = 30 }
                        }.buttonStyle(ToggleButton(isOn: .oneway { targetVideoFPS == 30 }))
                        Button("60fps") {
                            withAnimation(.spring()) { targetVideoFPS = 60 }
                        }.buttonStyle(ToggleButton(isOn: .oneway { targetVideoFPS == 60 }))
                        Button("1/2 of source") {
                            withAnimation(.spring()) { targetVideoFPS = -2 }
                        }.buttonStyle(ToggleButton(isOn: .oneway { targetVideoFPS == -2 }))
                        Button("1/4 of source") {
                            withAnimation(.spring()) { targetVideoFPS = -4 }
                        }.buttonStyle(ToggleButton(isOn: .oneway { targetVideoFPS == -4 }))
                    }.disabled(!capVideoFPS)
                }
                .accessibilityLabel("Cap frames per second")
                .searchAnchor("video.optimisationrules.capVideoFPS")
                if targetVideoFPS < 0, capVideoFPS {
                    HStack {
                        Text("but no less than").regular(TextSize.body).padding(.trailing, Space.s)
                            .searchAnchor("video.optimisationrules.minVideoFPS")
                        Spacer()

                        Button("10fps") {
                            minVideoFPS = 10
                        }.buttonStyle(ToggleButton(isOn: .oneway { minVideoFPS == 10 }))
                        Button("24fps") {
                            minVideoFPS = 24
                        }.buttonStyle(ToggleButton(isOn: .oneway { minVideoFPS == 24 }))
                        Button("30fps") {
                            minVideoFPS = 30
                        }.buttonStyle(ToggleButton(isOn: .oneway { minVideoFPS == 30 }))
                        Button("60fps") {
                            minVideoFPS = 60
                        }.buttonStyle(ToggleButton(isOn: .oneway { minVideoFPS == 60 }))
                    }
                    .padding(.leading, Space.s)
                }
                Picker(selection: $playbackSpeedFrameBehaviour) {
                    Text("Keep frames (smoother, higher fps)").tag(PlaybackSpeedFrameBehaviour.keepFrames)
                    Text("Drop frames (smaller file)").tag(PlaybackSpeedFrameBehaviour.dropFrames)
                } label: {
                    Text("Playback speed change").regular(TextSize.body)
                }
                .accessibilityLabel("Playback speed change")
                .searchAnchor("video.optimisationrules.playbackSpeedFrameBehaviour")

            }
            Section(header: SectionHeader(title: "Watched file filters", subtitle: "Only files within these limits are optimised")) {
                FileSizeRangeRow(minKB: $minVideoSizeKB, maxMB: $maxVideoSizeMB)
                    .searchAnchor("video.watchedfilefilters.minVideoSizeKB")
                ResolutionRangeRow(label: "Resolution", minRes: $minVideoResolution, maxRes: $maxVideoResolution)
                    .searchAnchor("video.watchedfilefilters.minVideoResolution")
                CountSliderRow(count: $maxVideoFileCount, caption: { "Skips optimisation when more than \($0) \($0 == 1 ? "video is" : "videos are") copied or moved at once" })
                    .searchAnchor("video.watchedfilefilters.maxVideoFileCount")
                HStack {
                    Text("Ignore videos with extension").regular(TextSize.body).padding(.trailing, Space.s)
                        .searchAnchor("video.watchedfilefilters.videoFormatsToSkip")
                    Spacer()

                    ForEach(VIDEO_FORMATS, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension!) {
                            videoFormatsToSkip.toggle(format)
                        }.buttonStyle(ToggleButton(isOn: .oneway { videoFormatsToSkip.contains(format) }))
                            .font(.mono(TextSize.subheadline))
                    }
                }
            }
            Section(header: SectionHeader(title: "Compatibility", subtitle: "Converts less known formats to more compatible ones before optimisation")) {
                HStack {
                    (Text("Convert to ").regular(TextSize.body) + Text("mp4").mono(TextSize.body)).padding(.trailing, Space.s)
                        .searchAnchor("video.compatibility.formatsToConvertToMP4")
                    Spacer()

                    ForEach(FORMATS_CONVERTIBLE_TO_MP4, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension!) {
                            formatsToConvertToMP4.toggle(format)
                        }.buttonStyle(ToggleButton(isOn: .oneway { formatsToConvertToMP4.contains(format) }))
                            .font(.mono(TextSize.subheadline))
                    }
                }
                Toggle("Convert audio to AAC", isOn: $convertAudioToAAC)
                    .searchAnchor("video.compatibility.convertAudioToAAC", namesControl: true)
            }
            .id("compatibility")
        }
        .scrollContentBackground(.hidden)
        .padding(Space.xs)
    }

    func videoCompressionTitle(_ tier: CompressionTier) -> String {
        switch tier {
        case .adaptive: "Adaptive"
        case .lossless: "Visually lossless"
        case .fast: "Hardware encoder"
        default: "Software encoder"
        }
    }

    func videoCompressionSubtitle(_ tier: CompressionTier) -> String {
        switch tier {
        case .adaptive: "Picks the best encoder and amount of compression for each file"
        case .lossless: "No perceptible quality loss"
        case .fast: "Fast, battery efficient, no CPU usage, modest size gains"
        default: "Slower, higher CPU usage, better quality and size gains"
        }
    }

    @State private var lastVideoFactor = 50

}

struct SectionHeader: View {
    var title: String
    var subtitle: String?

    var body: some View {
        Text(title).round(TextSize.title3, weight: .semibold)
            + (subtitle.map { Text("\n\($0)").font(.caption).foregroundColor(.secondary) } ?? Text(""))
    }
}

let DEFAULT_NAME_TEMPLATE = "polc_%y-%m-%d_%i"
let DEFAULT_SAME_FOLDER_NAME_TEMPLATE = "%f-optimised"
let DEFAULT_SPECIFIC_FOLDER_NAME_TEMPLATE = "%P/optimised/%f"

// MARK: - Compact template field (without token table) for inline use in File handling pane

struct CompactSameFolderTemplate: View {
    let type: PolcFileType
    @Binding var template: String

    /// The INPUT file extension shown in the example (e.g. "webp" for auto-convert, nil for optimise).
    var inputExtension: String?
    /// The OUTPUT file extension for the example (e.g. "jpeg" for auto-convert, nil = same as input).
    var outputExtension: String?

    /// Build the path used by the example generator: base stem + the OUTPUT extension
    /// (so the template is applied to the file that will actually be written).
    var examplePath: FilePath {
        let ext = outputExtension ?? inputExtension
        guard let ext else { return type.defaultNameTemplatePath }
        let base = type.defaultNameTemplatePath
        let stem = base.lastComponent?.stem ?? "shot"
        return base.removingLastComponent().appending("\(stem).\(ext)")
    }

    var inputName: String {
        let base = type.defaultNameTemplatePath
        let stem = base.lastComponent?.stem ?? "shot"
        if let ext = inputExtension {
            return "\(stem).\(ext)"
        }
        return base.lastComponent?.string ?? "shot.png"
    }

    var outputName: String {
        generateFileName(template: template ?! DEFAULT_SAME_FOLDER_NAME_TEMPLATE, for: examplePath, autoIncrementingNumber: &Defaults[.lastAutoIncrementingNumber])
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            TextField("", text: $template, prompt: Text(DEFAULT_SAME_FOLDER_NAME_TEMPLATE))
                .accessibilityLabel("File name template")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.xs)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .stroke(Color.gray, lineWidth: 1)
                )
            ExampleContainer(inputName: inputName, outputName: outputName, inputExt: inputExtension, outputExt: outputExtension)
                .layoutPriority(1)
        }
    }
}

struct CompactSpecificFolderTemplate: View {
    let type: PolcFileType
    @Binding var template: String

    /// The INPUT file extension shown in the example (e.g. "webp" for auto-convert, nil for optimise).
    var inputExtension: String?
    /// The OUTPUT file extension for the example (e.g. "jpeg" for auto-convert, nil = same as input).
    var outputExtension: String?

    /// Build the path used by the example generator: base stem + the OUTPUT extension.
    var examplePath: FilePath {
        let ext = outputExtension ?? inputExtension
        guard let ext else { return type.defaultNameTemplatePath }
        let base = type.defaultNameTemplatePath
        let stem = base.lastComponent?.stem ?? "shot"
        return base.removingLastComponent().appending("\(stem).\(ext)")
    }

    var inputName: String {
        let base = type.defaultNameTemplatePath
        let stem = base.lastComponent?.stem ?? "shot"
        if let ext = inputExtension {
            return "\(stem).\(ext)"
        }
        return base.lastComponent?.string ?? "shot.png"
    }

    var outputPath: String {
        (try? generateFilePath(
            template: template ?! DEFAULT_SPECIFIC_FOLDER_NAME_TEMPLATE,
            for: examplePath,
            autoIncrementingNumber: &Defaults[.lastAutoIncrementingNumber],
            mkdir: false
        ))?.flatMap(\.shellString) ?? "Invalid path"
    }

    /// Stores a pasted home path as `~/…` so the template still points somewhere real on the other
    /// Macs it syncs to, where the username differs.
    var portableTemplate: Binding<String> {
        Binding(get: { template }, set: { template = $0.portablePath })
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            TextField("", text: portableTemplate, prompt: Text(DEFAULT_SPECIFIC_FOLDER_NAME_TEMPLATE))
                .accessibilityLabel("Folder template")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.xs)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .stroke(Color.gray, lineWidth: 1)
                )
            ExampleContainer(inputName: inputName, outputName: outputPath, inputExt: inputExtension, outputExt: outputExtension)
                .layoutPriority(1)
        }
    }
}

// MARK: - Example container: "Example: [inputPill] becomes [outputPill]"

// The whole expression lives in a single bordered+bg element at the right of the row.

/// A filled muted pill for a filename token. Content-sized (fixedSize), mono font.
private struct ExampleFilePill: View {
    let name: String
    /// Tint for the capsule fill; nil = neutral grey.
    var tint: Color?

    var body: some View {
        Text(name)
            .font(.mono(TextSize.caption))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, Space.xs)
            .padding(.vertical, Space.xs)
            .fixedSize()
            .background(Capsule().fill(fillColor))
            .foregroundColor(.primary)
    }

    private var fillColor: Color {
        if let tint {
            return tint.opacity(0.11)
        }
        return Color(
            light: Color(white: 0.0).opacity(0.07),
            dark: Color(white: 1.0).opacity(0.10)
        )
    }

}

/// Wraps "Example: [in] becomes [out]" in a single subtle bordered container.
private struct ExampleContainer: View {
    let inputName: String
    let outputName: String
    // Extensions used purely for hue-tinting the pills (nil = neutral).
    var inputExt: String?
    var outputExt: String?

    var body: some View {
        HStack(spacing: Space.xs) {
            Text("Example:")
                .font(.round(TextSize.subheadline))
                .foregroundColor(.secondary)
                .fixedSize()
            ExampleFilePill(name: inputName, tint: tint(for: inputExt))
            Text("becomes")
                .font(.round(TextSize.subheadline))
                .foregroundColor(.secondary)
                .fixedSize()
            ExampleFilePill(name: middleTruncated(outputName), tint: tint(for: outputExt ?? inputExt))
        }
        .padding(.horizontal, Space.s)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(bgColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private static let extensionTints: [String: Color] = [
        "jpeg": Palette.image,
        "jpg": Palette.image,
        "png": Palette.image,
        "webp": Palette.image,
        "avif": Palette.image,
        "heic": Palette.image,
        "mp4": Palette.video,
        "mov": Palette.video,
        "m4a": Palette.audio,
        "mp3": Palette.audio,
        "ogg": Palette.audio,
        "pdf": Palette.pdf,
    ]

    private var bgColor: Color {
        Color(
            light: Color(white: 0.0).opacity(0.035),
            dark: Color(white: 1.0).opacity(0.06)
        )
    }

    /// Middle-truncate a long output path so the content-sized pill stays around 200px wide, leaving
    /// more room for the template field. The pill uses a 10pt monospaced font (~6px per glyph), so
    /// roughly 32 characters fit; longer strings keep the head and tail with an ellipsis in between.
    private func middleTruncated(_ s: String, maxChars: Int = 32) -> String {
        guard s.count > maxChars else { return s }
        let keep = maxChars - 1
        let head = keep / 2
        let tail = keep - head
        return "\(s.prefix(head))…\(s.suffix(tail))"
    }

    private func tint(for ext: String?) -> Color? {
        guard let ext else { return nil }
        return Self.extensionTints[ext.lowercased()]
    }

}

// MARK: - Auto-conversion pills

private struct PillView: View {
    let text: String
    let tint: Color // background tint (the raw hue)
    let textColor: Color // adaptive text colour

    var body: some View {
        Text(text)
            .font(.mono(TextSize.caption, weight: .medium))
            .padding(.horizontal, Space.xs)
            .padding(.vertical, Space.xs)
            .background(Capsule().fill(tint.opacity(0.15)))
            .foregroundColor(textColor)
    }
}

private struct AutoConvertPills: View {
    let groups: [FileHandlingSettingsView.ConvertGroup]
    let compatibilityTab: SettingsView.Tabs

    var body: some View {
        if !groups.isEmpty {
            HStack(spacing: Space.xs) {
                Text("Converts:")
                    .round(TextSize.subheadline)
                    .foregroundColor(.secondary)
                ForEach(groups.indices, id: \.self) { idx in
                    let group = groups[idx]
                    if idx > 0 {
                        Text("|")
                            .font(.mono(TextSize.caption, weight: .regular))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    PillView(text: group.sources.joined(separator: ", "), tint: .gray, textColor: .secondary)
                    Text("->")
                        .font(.mono(TextSize.caption, weight: .regular))
                        .foregroundColor(.secondary)
                    PillView(text: group.target, tint: group.targetColor, textColor: group.targetColor)
                }
                Spacer(minLength: 0)
                Button {
                    settingsViewManager.tab = compatibilityTab
                    settingsViewManager.scrollToCompatibility = true
                } label: {
                    HStack(spacing: Space.xs) {
                        Text("Configured in")
                        Text("Compatibility").underline()
                    }
                    .foregroundColor(.secondary.opacity(0.65))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in
                    if h {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .font(.round(TextSize.subheadline))
            }
        }
    }
}

/// A `Form` that scrolls down to the Section tagged `.id("compatibility")` when the
/// "Configured in Compatibility" link in File Handling requests it. Drop-in replacement
/// for `Form` in the Video / Audio / Images tabs; per-tab modifiers (formStyle,
/// scrollContentBackground, padding) still reach the form via the environment.
private struct CompatibilityScrollForm<Content: View>: View {
    @ObservedObject var svm = settingsViewManager

    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            Form { content }
                .onAppear { scroll(proxy) }
                .onChange(of: svm.scrollToCompatibility) { _ in scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard svm.scrollToCompatibility else { return }
        // Give the freshly switched-to tab a moment to lay out its sections before scrolling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation { proxy.scrollTo("compatibility", anchor: .top) }
            svm.scrollToCompatibility = false
        }
    }
}

/// Scrolls an enclosing scroll container down to the section tagged `.id("automation")` when an
/// assignment pill's "Go to" (clipboard / drop zone) requests it, and on appear for the just-switched
/// tab. Apply to the tab's `Form`/`ScrollView`; tag its Automation section with `.id("automation")`.
private struct ScrollToAutomation: ViewModifier {
    @ObservedObject var svm = settingsViewManager

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onAppear { scroll(proxy) }
                .onChange(of: svm.scrollToAutomation) { _ in scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard svm.scrollToAutomation else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation { proxy.scrollTo("automation", anchor: .top) }
            svm.scrollToAutomation = false
        }
    }
}

extension View {
    func scrollsToAutomation() -> some View {
        modifier(ScrollToAutomation())
    }
}

// MARK: - File handling settings tab

struct FileHandlingSettingsView: View {
    // MARK: - Auto-conversion pill groups

    struct ConvertGroup {
        let sources: [String]
        let target: String
        let targetColor: Color
    }

    // Optimised placement
    @Default(.optimisedImageBehaviour) var optimisedImageBehaviour
    @Default(.optimisedVideoBehaviour) var optimisedVideoBehaviour
    @Default(.optimisedAudioBehaviour) var optimisedAudioBehaviour
    @Default(.optimisedPDFBehaviour) var optimisedPDFBehaviour
    @Default(.sameFolderNameTemplateImage) var sameFolderNameTemplateImage
    @Default(.sameFolderNameTemplateVideo) var sameFolderNameTemplateVideo
    @Default(.sameFolderNameTemplateAudio) var sameFolderNameTemplateAudio
    @Default(.sameFolderNameTemplatePDF) var sameFolderNameTemplatePDF
    @Default(.specificFolderNameTemplateImage) var specificFolderNameTemplateImage
    @Default(.specificFolderNameTemplateVideo) var specificFolderNameTemplateVideo
    @Default(.specificFolderNameTemplateAudio) var specificFolderNameTemplateAudio
    @Default(.specificFolderNameTemplatePDF) var specificFolderNameTemplatePDF

    // Auto-conversion placement
    @Default(.convertedImageBehaviour) var convertedImageBehaviour
    @Default(.convertedVideoBehaviour) var convertedVideoBehaviour
    @Default(.convertedAudioBehaviour) var convertedAudioBehaviour

    // Manual conversion placement
    @Default(.manualConvertedImageBehaviour) var manualConvertedImageBehaviour
    @Default(.manualConvertedVideoBehaviour) var manualConvertedVideoBehaviour
    @Default(.manualConvertedAudioBehaviour) var manualConvertedAudioBehaviour

    // Shared conversion templates (used by both auto and manual convert rows)
    @Default(.convertedSameFolderNameTemplateImage) var convertedSameFolderNameTemplateImage
    @Default(.convertedSameFolderNameTemplateVideo) var convertedSameFolderNameTemplateVideo
    @Default(.convertedSameFolderNameTemplateAudio) var convertedSameFolderNameTemplateAudio
    @Default(.convertedSpecificFolderNameTemplateImage) var convertedSpecificFolderNameTemplateImage
    @Default(.convertedSpecificFolderNameTemplateVideo) var convertedSpecificFolderNameTemplateVideo
    @Default(.convertedSpecificFolderNameTemplateAudio) var convertedSpecificFolderNameTemplateAudio

    // Format lists for context text
    @Default(.formatsToConvertToJPEG) var formatsToConvertToJPEG
    @Default(.formatsToConvertToPNG) var formatsToConvertToPNG
    @Default(.formatsToConvertToMP4) var formatsToConvertToMP4
    @Default(.formatsToConvertToAAC) var formatsToConvertToAAC
    @Default(.formatsToConvertToMP3) var formatsToConvertToMP3

    var body: some View {
        Form {
            // MARK: Images

            Section(header: SectionHeader(title: "Images")) {
                // Optimise row: picker + optional template in a single Form row (no divider between them).
                VStack(alignment: .leading, spacing: Space.xs) {
                    Picker(selection: $optimisedImageBehaviour) {
                        Text("Temporary folder").tag(FileBehaviour.temporary)
                        Text("In place (replace original)").tag(FileBehaviour.inPlace)
                        Text("Same folder as original").tag(FileBehaviour.sameFolder)
                        Text("Specific folder").tag(FileBehaviour.specificFolder)
                    } label: {
                        settingLabel("Optimised file placement", "Where the smaller file is saved, and whether it replaces the original")
                    }
                    .searchAnchor("files.images.optimisedImageBehaviour", namesControl: true)
                    if optimisedImageBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .image, template: $sameFolderNameTemplateImage)
                            .searchAnchor("files.images.sameFolderNameTemplateImage")
                    } else if optimisedImageBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .image, template: $specificFolderNameTemplateImage)
                            .searchAnchor("files.images.specificFolderNameTemplateImage")
                    }
                }

                // Auto-convert row: picker + Converts pills + optional template in a single Form row.
                VStack(alignment: .leading, spacing: Space.xs) {
                    Picker(selection: $convertedImageBehaviour) {
                        Text("Temporary folder").tag(FileBehaviour.temporary)
                        Text("In place (replace original)").tag(FileBehaviour.inPlace)
                        Text("Same folder as original").tag(FileBehaviour.sameFolder)
                        Text("Specific folder").tag(FileBehaviour.specificFolder)
                    } label: {
                        settingLabel("Auto-conversion behaviour for compatible formats", "Formats that many apps cannot open well are converted to a widely supported one automatically before optimising.")
                    }
                    .searchAnchor("files.images.convertedImageBehaviour", namesControl: true)
                    AutoConvertPills(groups: imageAutoConvertGroups, compatibilityTab: .images)
                    if convertedImageBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .image, template: $convertedSameFolderNameTemplateImage, inputExtension: autoImageInputExt, outputExtension: autoImageOutputExt)
                            .searchAnchor("files.images.convertedSameFolderNameTemplateImage")
                    } else if convertedImageBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .image, template: $convertedSpecificFolderNameTemplateImage, inputExtension: autoImageInputExt, outputExtension: autoImageOutputExt)
                            .searchAnchor("files.images.convertedSpecificFolderNameTemplateImage")
                    }
                }

                // Manual-convert row: picker + optional template in a single Form row.
                VStack(alignment: .leading, spacing: Space.xs) {
                    Picker(selection: $manualConvertedImageBehaviour) {
                        Text("Temporary folder").tag(FileBehaviour.temporary)
                        Text("In place (replace original)").tag(FileBehaviour.inPlace)
                        Text("Same folder as original").tag(FileBehaviour.sameFolder)
                        Text("Specific folder").tag(FileBehaviour.specificFolder)
                    } label: {
                        settingLabel("Manual conversion behaviour", "When you pick a new format by clicking the file extension on a floating result, or via the submenu **Convert to...** in the right-click menu.")
                    }
                    .searchAnchor("files.images.manualConvertedImageBehaviour", namesControl: true)
                    if manualConvertedImageBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .image, template: $convertedSameFolderNameTemplateImage, inputExtension: "jpeg", outputExtension: "webp")
                    } else if manualConvertedImageBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .image, template: $convertedSpecificFolderNameTemplateImage, inputExtension: "jpeg", outputExtension: "webp")
                    }
                }

                if imageHasTemplateRow {
                    templateVarsCollapsible(for: .image)
                }
            }

            // MARK: Videos

            Section(header: SectionHeader(title: "Videos")) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Picker(selection: $optimisedVideoBehaviour) {
                        Text("Temporary folder").tag(FileBehaviour.temporary)
                        Text("In place (replace original)").tag(FileBehaviour.inPlace)
                        Text("Same folder as original").tag(FileBehaviour.sameFolder)
                        Text("Specific folder").tag(FileBehaviour.specificFolder)
                    } label: {
                        settingLabel("Optimised file placement", "Where the smaller file is saved, and whether it replaces the original")
                    }
                    .searchAnchor("files.videos.optimisedVideoBehaviour", namesControl: true)
                    if optimisedVideoBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .video, template: $sameFolderNameTemplateVideo)
                            .searchAnchor("files.videos.sameFolderNameTemplateVideo")
                    } else if optimisedVideoBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .video, template: $specificFolderNameTemplateVideo)
                            .searchAnchor("files.videos.specificFolderNameTemplateVideo")
                    }
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Picker(selection: $convertedVideoBehaviour) {
                        Text("Temporary folder").tag(FileBehaviour.temporary)
                        Text("In place (replace original)").tag(FileBehaviour.inPlace)
                        Text("Same folder as original").tag(FileBehaviour.sameFolder)
                        Text("Specific folder").tag(FileBehaviour.specificFolder)
                    } label: {
                        settingLabel("Auto-conversion behaviour for compatible formats", "Formats that many apps cannot open well are converted to a widely supported one automatically before optimising.")
                    }
                    .searchAnchor("files.videos.convertedVideoBehaviour", namesControl: true)
                    AutoConvertPills(groups: videoAutoConvertGroups, compatibilityTab: .video)
                    if convertedVideoBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .video, template: $convertedSameFolderNameTemplateVideo, inputExtension: autoVideoInputExt, outputExtension: "mp4")
                            .searchAnchor("files.videos.convertedSameFolderNameTemplateVideo")
                    } else if convertedVideoBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .video, template: $convertedSpecificFolderNameTemplateVideo, inputExtension: autoVideoInputExt, outputExtension: "mp4")
                            .searchAnchor("files.videos.convertedSpecificFolderNameTemplateVideo")
                    }
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Picker(selection: $manualConvertedVideoBehaviour) {
                        Text("Temporary folder").tag(FileBehaviour.temporary)
                        Text("In place (replace original)").tag(FileBehaviour.inPlace)
                        Text("Same folder as original").tag(FileBehaviour.sameFolder)
                        Text("Specific folder").tag(FileBehaviour.specificFolder)
                    } label: {
                        settingLabel("Manual conversion behaviour", "When you pick a new format by clicking the file extension on a floating result, or via the submenu **Convert to...** in the right-click menu.")
                    }
                    .searchAnchor("files.videos.manualConvertedVideoBehaviour", namesControl: true)
                    if manualConvertedVideoBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .video, template: $convertedSameFolderNameTemplateVideo, inputExtension: "mov", outputExtension: "mp4")
                    } else if manualConvertedVideoBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .video, template: $convertedSpecificFolderNameTemplateVideo, inputExtension: "mov", outputExtension: "mp4")
                    }
                }

                if videoHasTemplateRow {
                    templateVarsCollapsible(for: .video)
                }
            }

            // MARK: Audio

            Section(header: SectionHeader(title: "Audio")) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Picker(selection: $optimisedAudioBehaviour) {
                        Text("Temporary folder").tag(FileBehaviour.temporary)
                        Text("In place (replace original)").tag(FileBehaviour.inPlace)
                        Text("Same folder as original").tag(FileBehaviour.sameFolder)
                        Text("Specific folder").tag(FileBehaviour.specificFolder)
                    } label: {
                        settingLabel("Optimised file placement", "Where the smaller file is saved, and whether it replaces the original")
                    }
                    .searchAnchor("files.audio.optimisedAudioBehaviour", namesControl: true)
                    if optimisedAudioBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .audio, template: $sameFolderNameTemplateAudio)
                            .searchAnchor("files.audio.sameFolderNameTemplateAudio")
                    } else if optimisedAudioBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .audio, template: $specificFolderNameTemplateAudio)
                            .searchAnchor("files.audio.specificFolderNameTemplateAudio")
                    }
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Picker(selection: $convertedAudioBehaviour) {
                        Text("Temporary folder").tag(FileBehaviour.temporary)
                        Text("In place (replace original)").tag(FileBehaviour.inPlace)
                        Text("Same folder as original").tag(FileBehaviour.sameFolder)
                        Text("Specific folder").tag(FileBehaviour.specificFolder)
                    } label: {
                        settingLabel("Auto-conversion behaviour for compatible formats", "Formats that many apps cannot open well are converted to a widely supported one automatically before optimising.")
                    }
                    .searchAnchor("files.audio.convertedAudioBehaviour", namesControl: true)
                    AutoConvertPills(groups: audioAutoConvertGroups, compatibilityTab: .audio)
                    if convertedAudioBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .audio, template: $convertedSameFolderNameTemplateAudio, inputExtension: autoAudioInputExt, outputExtension: autoAudioOutputExt)
                            .searchAnchor("files.audio.convertedSameFolderNameTemplateAudio")
                    } else if convertedAudioBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .audio, template: $convertedSpecificFolderNameTemplateAudio, inputExtension: autoAudioInputExt, outputExtension: autoAudioOutputExt)
                            .searchAnchor("files.audio.convertedSpecificFolderNameTemplateAudio")
                    }
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Picker(selection: $manualConvertedAudioBehaviour) {
                        Text("Temporary folder").tag(FileBehaviour.temporary)
                        Text("In place (replace original)").tag(FileBehaviour.inPlace)
                        Text("Same folder as original").tag(FileBehaviour.sameFolder)
                        Text("Specific folder").tag(FileBehaviour.specificFolder)
                    } label: {
                        settingLabel("Manual conversion behaviour", "When you pick a new format by clicking the file extension on a floating result, or via the submenu **Convert to...** in the right-click menu.")
                    }
                    .searchAnchor("files.audio.manualConvertedAudioBehaviour", namesControl: true)
                    if manualConvertedAudioBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .audio, template: $convertedSameFolderNameTemplateAudio, inputExtension: "wav", outputExtension: "mp3")
                    } else if manualConvertedAudioBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .audio, template: $convertedSpecificFolderNameTemplateAudio, inputExtension: "wav", outputExtension: "mp3")
                    }
                }

                if audioHasTemplateRow {
                    templateVarsCollapsible(for: .audio)
                }
            }

            // MARK: PDF

            Section(header: SectionHeader(title: "PDF")) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Picker(selection: $optimisedPDFBehaviour) {
                        Text("Temporary folder").tag(FileBehaviour.temporary)
                        Text("In place (replace original)").tag(FileBehaviour.inPlace)
                        Text("Same folder as original").tag(FileBehaviour.sameFolder)
                        Text("Specific folder").tag(FileBehaviour.specificFolder)
                    } label: {
                        settingLabel("Optimised file placement", "Where the smaller file is saved, and whether it replaces the original")
                    }
                    .searchAnchor("files.pdf.optimisedPDFBehaviour", namesControl: true)
                    if optimisedPDFBehaviour == .sameFolder {
                        CompactSameFolderTemplate(type: .pdf, template: $sameFolderNameTemplatePDF)
                            .searchAnchor("files.pdf.sameFolderNameTemplatePDF")
                    } else if optimisedPDFBehaviour == .specificFolder {
                        CompactSpecificFolderTemplate(type: .pdf, template: $specificFolderNameTemplatePDF)
                            .searchAnchor("files.pdf.specificFolderNameTemplatePDF")
                    }
                }

                if pdfHasTemplateRow {
                    templateVarsCollapsible(for: .pdf)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(Space.xs)
    }

    @State private var expandedVars: Set<PolcFileType> = []

    // MARK: - Per-section helpers

    // MARK: Dynamic example extensions for auto-convert rows

    /// Image auto-convert: prefer webp->jpeg; fall back to first-of-toJPEG or first-of-toPNG.
    private var autoImageInputExt: String? {
        if formatsToConvertToJPEG.contains(where: { $0.preferredFilenameExtension == "webp" }) {
            return "webp"
        }
        if let first = formatsToConvertToJPEG.compactMap(\.preferredFilenameExtension).sorted().first {
            return first
        }
        return formatsToConvertToPNG.compactMap(\.preferredFilenameExtension).sorted().first
    }

    private var autoImageOutputExt: String? {
        if formatsToConvertToJPEG.contains(where: { $0.preferredFilenameExtension == "webp" }) || !formatsToConvertToJPEG.isEmpty {
            return "jpeg"
        }
        if !formatsToConvertToPNG.isEmpty {
            return "png"
        }
        return nil
    }

    /// Video auto-convert: first extension from formatsToConvertToMP4; output is always mp4.
    private var autoVideoInputExt: String? {
        formatsToConvertToMP4.compactMap(\.preferredFilenameExtension).sorted().first
    }

    /// Audio auto-convert: first source extension across both target sets; output depends on which set it comes from.
    private var autoAudioInputExt: String? {
        let aacExts = formatsToConvertToAAC.compactMap(\.preferredFilenameExtension).sorted()
        let mp3Exts = formatsToConvertToMP3.compactMap(\.preferredFilenameExtension).sorted()
        return (aacExts + mp3Exts).sorted().first
    }

    private var autoAudioOutputExt: String? {
        guard let inputExt = autoAudioInputExt else { return nil }
        let aacExts = formatsToConvertToAAC.compactMap(\.preferredFilenameExtension)
        if aacExts.contains(inputExt) {
            return "m4a"
        }
        let mp3Exts = formatsToConvertToMP3.compactMap(\.preferredFilenameExtension)
        if mp3Exts.contains(inputExt) {
            return "mp3"
        }
        return nil
    }

    private var imageHasTemplateRow: Bool {
        [optimisedImageBehaviour, convertedImageBehaviour, manualConvertedImageBehaviour].contains(where: { $0 == .sameFolder || $0 == .specificFolder })
    }

    private var videoHasTemplateRow: Bool {
        [optimisedVideoBehaviour, convertedVideoBehaviour, manualConvertedVideoBehaviour].contains(where: { $0 == .sameFolder || $0 == .specificFolder })
    }

    private var audioHasTemplateRow: Bool {
        [optimisedAudioBehaviour, convertedAudioBehaviour, manualConvertedAudioBehaviour].contains(where: { $0 == .sameFolder || $0 == .specificFolder })
    }

    private var pdfHasTemplateRow: Bool {
        optimisedPDFBehaviour == .sameFolder || optimisedPDFBehaviour == .specificFolder
    }

    private var imageAutoConvertGroups: [ConvertGroup] {
        var groups: [ConvertGroup] = []
        let toJPEG = formatsToConvertToJPEG.compactMap { $0.preferredFilenameExtension?.uppercased() }.sorted()
        if !toJPEG.isEmpty {
            groups.append(ConvertGroup(
                sources: toJPEG,
                target: "JPEG",
                targetColor: Palette.image
            ))
        }
        let toPNG = formatsToConvertToPNG.compactMap { $0.preferredFilenameExtension?.uppercased() }.sorted()
        if !toPNG.isEmpty {
            groups.append(ConvertGroup(
                sources: toPNG,
                target: "PNG",
                targetColor: Palette.image
            ))
        }
        return groups
    }

    private var videoAutoConvertGroups: [ConvertGroup] {
        let fmts = formatsToConvertToMP4.compactMap { $0.preferredFilenameExtension?.uppercased() }.sorted()
        guard !fmts.isEmpty else { return [] }
        return [ConvertGroup(
            sources: fmts,
            target: "MP4",
            targetColor: Palette.video
        )]
    }

    private var audioAutoConvertGroups: [ConvertGroup] {
        var groups: [ConvertGroup] = []
        let toAAC = formatsToConvertToAAC.compactMap { $0.preferredFilenameExtension?.uppercased() }.sorted()
        if !toAAC.isEmpty {
            groups.append(ConvertGroup(
                sources: toAAC,
                target: "AAC (M4A)",
                targetColor: Palette.audio
            ))
        }
        let toMP3 = formatsToConvertToMP3.compactMap { $0.preferredFilenameExtension?.uppercased() }.sorted()
        if !toMP3.isEmpty {
            groups.append(ConvertGroup(
                sources: toMP3,
                target: "MP3",
                targetColor: Palette.audio
            ))
        }
        return groups
    }

    @ViewBuilder
    private func templateVarsCollapsible(for type: PolcFileType) -> some View {
        let expanded = expandedVars.contains(type)
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeOut(duration: 0.15)) {
                if expandedVars.contains(type) {
                    expandedVars.remove(type)
                } else {
                    expandedVars.insert(type)
                }
            }}) {
                HStack(spacing: Space.xs) {
                    SwiftUI.Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.semibold(TextSize.caption)).foregroundColor(.secondary)
                    Text("Template variables").semibold(TextSize.callout)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(alignment: .top) {
                        Text("""
                        **Date**                | **Time**
                        --------------------|-----------------
                        Year             **%y** | Hour     **%H**
                        Month (numeric)  **%m** | Minutes  **%M**
                        Month (name)     **%n** | Seconds  **%S**
                        Day              **%d** | AM/PM    **%p**
                        Weekday          **%w** |
                        """)
                        Spacer()
                        Text("""
                        Source file path (without name)        **%P**
                        Source file name (without extension)   **%f**
                        Source file extension                  **%e**

                        Random characters                      **%r**
                        Auto-incrementing number               **%i**
                        """)
                    }
                    .font(.mono(TextSize.subheadline, weight: .light))
                    .foregroundColor(.secondary)
                    .padding(Space.xs)
                }
                .padding(.top, Space.xs)
            }
        }
        .padding(.top, Space.xs)
    }

}

struct AudioSettingsView: View {
    @Default(.audioDirs) var audioDirs
    @Default(.audioCoverArt) var audioCoverArt
    @Default(.audioBitrate) var audioBitrate
    @Default(.audioCompression) var audioCompression
    @Default(.audioFormatsToSkip) var audioFormatsToSkip
    @Default(.formatsToConvertToAAC) var formatsToConvertToAAC
    @Default(.formatsToConvertToMP3) var formatsToConvertToMP3
    @Default(.maxAudioSizeMB) var maxAudioSizeMB
    @Default(.minAudioSizeKB) var minAudioSizeKB
    @Default(.maxAudioFileCount) var maxAudioFileCount
    @Default(.enableAutomaticAudioOptimisations) var enableAutomaticAudioOptimisations

    /// Reveals what the abstract percentage maps to in real bitrates (all formats use VBR).
    var audioCompressionCaption: String {
        let aac = audioCompression.audioBitrate(for: .aac) ?? 0
        let mp3 = audioCompression.audioBitrate(for: .mp3) ?? 0
        return "Around \(aac) kbps for AAC, \(mp3) for MP3 (variable bitrate). WAV, AIFF and FLAC are lossless, so the compression factor does not apply to them."
    }

    var body: some View {
        CompatibilityScrollForm {
            Section(header: SectionHeader(title: "Watch paths", subtitle: "Optimise audio files as they appear in these folders")) {
                DirListView(fileType: .audio, dirs: $audioDirs, enabled: $enableAutomaticAudioOptimisations)
            }
            .searchAnchor("audio.watchpaths.audioDirs")
            Section(header: SectionHeader(title: "Optimisation rules")) {
                HStack(spacing: Space.xs) {
                    SwiftUI.Image(systemName: "folder.badge.gearshape")
                    Text("Where files go is set in").foregroundColor(.secondary)
                    Button("File handling") { settingsViewManager.tab = .files }.buttonStyle(.link)
                }.font(.system(size: TextSize.subheadline))
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.s) {
                        Text("Compression").regular(TextSize.body)
                            .searchAnchor("audio.optimisationrules.audioCompression")
                        Slider(
                            value: Binding(
                                get: { Double(audioCompression.factor) },
                                set: { audioCompression.factor = Int($0.rounded()) }
                            ),
                            in: 5 ... 100, step: 1
                        )
                        .accessibilityLabel("Compression")
                        Text("\(audioCompression.factor)%")
                            .mono(TextSize.subheadline).foregroundColor(.secondary).frame(width: 38, alignment: .trailing)
                    }
                    Text(audioCompressionCaption).round(TextSize.caption, weight: .regular).foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    Picker(selection: $audioCoverArt) {
                        ForEach(AudioCoverArtBehaviour.allCases, id: \.self) { behaviour in
                            Text(behaviour.name).tag(behaviour)
                        }
                    } label: {
                        Text("Cover art").regular(TextSize.body)
                            .searchAnchor("audio.optimisationrules.audioCoverArt")
                    }
                    .accessibilityLabel("Cover art")
                    Text("Cover art is kept only for formats that can store it (AAC, MP3, FLAC); it is dropped for others.")
                        .round(TextSize.caption, weight: .regular).foregroundColor(.secondary)
                }
            }
            Section(header: SectionHeader(title: "Watched file filters", subtitle: "Only files within these limits are optimised")) {
                FileSizeRangeRow(minKB: $minAudioSizeKB, maxMB: $maxAudioSizeMB)
                    .searchAnchor("audio.watchedfilefilters.minAudioSizeKB")
                CountSliderRow(count: $maxAudioFileCount, caption: { "Skips optimisation when more than \($0) \($0 == 1 ? "audio file is" : "audio files are") copied or moved at once" })
                    .searchAnchor("audio.watchedfilefilters.maxAudioFileCount")
            }
            Section(header: SectionHeader(title: "Compatibility", subtitle: "Convert less compatible formats to AAC or MP3 before optimisation; anything not picked keeps its own format")) {
                HStack {
                    (Text("Convert to ").regular(TextSize.body) + Text("AAC (M4A)").mono(TextSize.body)).padding(.trailing, Space.s)
                    Spacer()
                    ForEach(FORMATS_CONVERTIBLE_TO_COMPRESSED_AUDIO, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension ?? format.identifier) {
                            formatsToConvertToAAC.toggle(format)
                            if formatsToConvertToAAC.contains(format) {
                                formatsToConvertToMP3.remove(format)
                            }
                        }.buttonStyle(ToggleButton(isOn: .oneway { formatsToConvertToAAC.contains(format) }))
                            .font(.mono(TextSize.subheadline))
                    }
                }
                HStack {
                    (Text("Convert to ").regular(TextSize.body) + Text("MP3").mono(TextSize.body)).padding(.trailing, Space.s)
                    Spacer()
                    ForEach(FORMATS_CONVERTIBLE_TO_COMPRESSED_AUDIO, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension ?? format.identifier) {
                            formatsToConvertToMP3.toggle(format)
                            if formatsToConvertToMP3.contains(format) {
                                formatsToConvertToAAC.remove(format)
                            }
                        }.buttonStyle(ToggleButton(isOn: .oneway { formatsToConvertToMP3.contains(format) }))
                            .font(.mono(TextSize.subheadline))
                    }
                }
            }
            .id("compatibility")
            .searchAnchor("audio.compatibility.formatsToConvertToMP3")
            .searchAnchor("audio.compatibility.formatsToConvertToAAC")
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

struct ImagesSettingsView: View {
    @Default(.imageDirs) var imageDirs
    @Default(.formatsToConvertToJPEG) var formatsToConvertToJPEG
    @Default(.formatsToConvertToPNG) var formatsToConvertToPNG
    @Default(.maxImageSizeMB) var maxImageSizeMB
    @Default(.minImageSizeKB) var minImageSizeKB
    @Default(.minImageResolution) var minImageResolution
    @Default(.maxImageResolution) var maxImageResolution
    @Default(.imageFormatsToSkip) var imageFormatsToSkip
    @Default(.adaptiveImageSize) var adaptiveImageSize
    @Default(.imageCompression) var imageCompression
    @Default(.convertHDRToSDR) var convertHDRToSDR
    // @Default(.downscaleRetinaImages) var downscaleRetinaImages
    @Default(.maxImageFileCount) var maxImageFileCount
    @Default(.copyImageFilePath) var copyImageFilePath
    @Default(.customNameTemplateForClipboardImages) var customNameTemplateForClipboardImages
    @Default(.useCustomNameTemplateForClipboardImages) var useCustomNameTemplateForClipboardImages
    @Default(.enablePhotosIntegration) var enablePhotosIntegration
    @Default(.maxCopiedPhotosCount) var maxCopiedPhotosCount
    @Default(.maxPhotosLength) var maxPhotosLength
    @Default(.photoCropOrientation) var photoCropOrientation

    @Default(.useAggressiveOptimisationJPEG) var useAggressiveOptimisationJPEG
    @Default(.useAggressiveOptimisationPNG) var useAggressiveOptimisationPNG
    @Default(.useAggressiveOptimisationGIF) var useAggressiveOptimisationGIF
    @Default(.gifFrameDropBehaviour) var gifFrameDropBehaviour
    @Default(.enableAutomaticImageOptimisations) var enableAutomaticImageOptimisations

    var maxPhotosLengthBinding: Binding<String> {
        Binding(
            get: { maxPhotosLength?.description ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let val = Int(trimmed) {
                    maxPhotosLength = val.capped(between: 1, and: 20000)
                } else {
                    maxPhotosLength = nil
                }
            }
        )
    }

    var customNameTemplate: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            settingLabel("Custom name template", "Rename the file using this template before copying the path to the clipboard")

            VStack(alignment: .leading) {
                TextField("", text: $customNameTemplateForClipboardImages, prompt: Text(DEFAULT_NAME_TEMPLATE))
                    .accessibilityLabel("Custom name template")
                    .frame(width: TEXT_FIELD_WIDTH, height: 18, alignment: .leading)
                    .padding(Space.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous).stroke(Color.gray.opacity(useCustomNameTemplateForClipboardImages ? 1 : 0.35), lineWidth: 1).scaleEffect(y: TEXT_FIELD_SCALE)
                            .offset(x: TEXT_FIELD_OFFSET)
                    )
                    .disabled(!useCustomNameTemplateForClipboardImages)
                    .searchAnchor("images.main.customNameTemplateForClipboardImages", namesControl: true)
                if useCustomNameTemplateForClipboardImages {
                    Text("Result: " + generateFileName(template: customNameTemplateForClipboardImages ?! DEFAULT_NAME_TEMPLATE, autoIncrementingNumber: &Defaults[.lastAutoIncrementingNumber]))
                        .round(TextSize.callout)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .truncationMode(.middle)
                        .foregroundColor(.secondary)
                        .offset(x: 6)
                }
            }
            if useCustomNameTemplateForClipboardImages {
                Text("""
                **Date**                | **Time**
                --------------------|-----------------
                Year             **%y** | Hour     **%H**
                Month (numeric)  **%m** | Minutes  **%M**
                Month (name)     **%n** | Seconds  **%S**
                Day              **%d** | AM/PM    **%p**
                Weekday          **%w** |

                Random characters **%r**
                Auto-incrementing number **%i**
                """)
                .mono(TextSize.callout, weight: .light)
                .foregroundColor(.secondary)
                .padding(.top, Space.xs)
            }
        }

    }

    var cropOrientationPicker: some View {
        Picker("Orientation", selection: $photoCropOrientation) {
            Label("height", systemImage: "rectangle.portrait").tag(CropOrientation.portrait)
                .help("Resize images until the height is equal or lower than the specified size.")
            Label("longest edge", systemImage: "sparkles.rectangle.stack").tag(CropOrientation.adaptive)
                .help("Resize images until the longest edge is equal or lower than the specified size.")
            Label("width", systemImage: "rectangle").tag(CropOrientation.landscape)
                .help("Resize images until the width is equal or lower than the specified size.")
        }
        .labelsHidden()
        .fixedSize()
        .pickerStyle(.segmented)
        .labelStyle(.titleAndIcon)
        .font(.heavy(TextSize.caption))
        .searchAnchor("images.main.photoCropOrientation")
    }

    var body: some View {
        CompatibilityScrollForm {
            Section(header: SectionHeader(title: "Watch paths", subtitle: "Optimise images as they appear in these folders")) {
                DirListView(fileType: .image, dirs: $imageDirs, enabled: $enableAutomaticImageOptimisations)
            }
            .searchAnchor("images.watchpaths.imageDirs")
            Section(header: SectionHeader(title: "File name handling")) {
                Toggle(isOn: $copyImageFilePath) {
                    settingLabel("Copy image paths", "When copying optimised image data, also copy the path of the image file")
                }
                .searchAnchor("images.filenamehandling.copyImageFilePath", namesControl: true)
                Toggle(isOn: $useCustomNameTemplateForClipboardImages.animation(.default)) {
                    customNameTemplate
                }.disabled(!copyImageFilePath)
                    .accessibilityLabel("Custom name template")
                    .searchAnchor("images.filenamehandling.useCustomNameTemplateForClipboardImages")
            }

            Section(header: SectionHeader(title: "Photos integration", subtitle: "Handle images copied from the Photos app")) {
                Toggle(isOn: $enablePhotosIntegration.animation(.spring())) {
                    Text("Optimise images copied from Photos.app").regular(TextSize.body)
                }
                .searchAnchor("images.photosintegration.enablePhotosIntegration", namesControl: true)

                CountSliderRow(count: $maxCopiedPhotosCount, range: 1 ... 50, caption: { "Skips optimisation when more than \($0) \($0 == 1 ? "photo is" : "photos are") copied at once" })
                    .disabled(!enablePhotosIntegration)
                    .searchAnchor("images.photosintegration.maxCopiedPhotosCount")

                HStack(spacing: Space.xs) {
                    Text("Downscale to").regular(TextSize.body).lineLimit(1).fixedSize()
                        .searchAnchor("images.photosintegration.maxPhotosLength")
                    // No .fixedSize() here: it collapses the field to its ideal width, which is ~0
                    // while the value is unset, leaving nothing to click inside the 70pt frame.
                    TextField("", text: maxPhotosLengthBinding)
                        .accessibilityLabel("Downscale to")
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70, alignment: .trailing)
                        .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).stroke(Color.gray, lineWidth: 1).scaleEffect(y: TEXT_FIELD_SCALE).offset(x: TEXT_FIELD_OFFSET))
                    Text("px").mono(TextSize.body).opacity(maxPhotosLength != nil ? 1 : 0.3).lineLimit(1).fixedSize()
                    Text("on").regular(TextSize.body).lineLimit(1).fixedSize()
                        .searchAnchor("images.photosintegration.photoCropOrientation")
                    Spacer()
                    cropOrientationPicker
                }
                .disabled(!enablePhotosIntegration)
            }

            Section(header: SectionHeader(title: "Optimisation rules")) {
                HStack(spacing: Space.xs) {
                    SwiftUI.Image(systemName: "folder.badge.gearshape")
                    Text("Where files go is set in").foregroundColor(.secondary)
                    Button("File handling") { settingsViewManager.tab = .files }.buttonStyle(.link)
                }.font(.system(size: TextSize.subheadline))

                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.s) {
                        Text("Compression").regular(TextSize.body)
                            .searchAnchor("images.optimisationrules.imageCompression")
                        Slider(
                            value: Binding(
                                get: { Double(imageCompression.factor) },
                                set: { imageCompression.factor = Int($0.rounded()) }
                            ),
                            in: 5 ... 100, step: 1
                        )
                        .accessibilityLabel("Compression")
                        .disabled(imageCompression.tier == .adaptive)
                        Text("\(imageCompression.factor)%")
                            .mono(TextSize.subheadline).foregroundColor(.secondary)
                            .opacity(imageCompression.tier == .adaptive ? 0.2 : 1)
                            .frame(width: 38, alignment: .trailing)
                        Button("Adaptive") {
                            imageCompression.tier = imageCompression.tier == .adaptive ? .custom : .adaptive
                        }
                        .buttonStyle(ToggleButton(isOn: .oneway { imageCompression.tier == .adaptive }))
                        .font(.mono(TextSize.subheadline))
                        .help("Convert detail heavy images to JPEG and low-detail ones to PNG, ignoring the compression factor's format")
                    }
                    if imageCompression.tier == .adaptive {
                        Text("Polc will automatically pick between JPEG or PNG conversion based on image entropy, and choose a fitting compression factor adaptively")
                            .round(TextSize.caption, weight: .regular).foregroundColor(.secondary)
                    }
                }
                Picker(selection: $gifFrameDropBehaviour) {
                    Text("Play faster").tag(GIFFrameDropBehaviour.playFaster)
                    Text("Keep duration (choppier motion)").tag(GIFFrameDropBehaviour.keepDuration)
                } label: {
                    Text("GIF frame dropping").regular(TextSize.body)
                        + Text("\nCompression factors above 80% drop every 4th, 3rd or 2nd frame of animated GIFs. The animation can either play faster with the remaining frames, or keep its duration by showing each frame longer").round(
                            11,
                            weight: .regular
                        ).foregroundColor(.secondary)
                }
                .searchAnchor("images.optimisationrules.gifFrameDropBehaviour", namesControl: true)
                Toggle(isOn: $convertHDRToSDR) {
                    Text("Convert HDR to SDR").regular(TextSize.body)
                }
                .searchAnchor("images.optimisationrules.convertHDRToSDR", namesControl: true)
                // Toggle(isOn: $downscaleRetinaImages) {
                //     Text("Downscale HiDPI images to 72 DPI").regular(13)
                //         + Text("\nScales down images taken on HiDPI screens to the standard DPI for web (e.g. Retina to 1x)").round(11, weight: .regular).foregroundColor(.secondary)
                // }

            }
            Section(header: SectionHeader(title: "Watched file filters", subtitle: "Only files within these limits are optimised")) {
                FileSizeRangeRow(minKB: $minImageSizeKB, maxMB: $maxImageSizeMB)
                    .searchAnchor("images.watchedfilefilters.minImageSizeKB")
                ResolutionRangeRow(label: "Resolution", minRes: $minImageResolution, maxRes: $maxImageResolution)
                    .searchAnchor("images.watchedfilefilters.minImageResolution")
                CountSliderRow(count: $maxImageFileCount, caption: { "Skips optimisation when more than \($0) \($0 == 1 ? "image is" : "images are") copied or moved at once" })
                    .searchAnchor("images.watchedfilefilters.maxImageFileCount")
                HStack {
                    Text("Ignore images with extension").regular(TextSize.body).padding(.trailing, Space.s)
                        .searchAnchor("images.watchedfilefilters.imageFormatsToSkip")
                    Spacer()

                    ForEach(IMAGE_FORMATS, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension!) {
                            imageFormatsToSkip.toggle(format)
                        }.buttonStyle(ToggleButton(isOn: .oneway { imageFormatsToSkip.contains(format) }))
                            .font(.mono(TextSize.subheadline))
                    }
                }
            }
            Section(header: SectionHeader(title: "Compatibility", subtitle: "Converts less known formats to more compatible ones before optimisation")) {
                HStack {
                    (Text("Convert to ").regular(TextSize.body) + Text("jpeg").mono(TextSize.body)).padding(.trailing, Space.s)
                        .searchAnchor("images.compatibility.formatsToConvertToJPEG")
                    Spacer()

                    ForEach(FORMATS_CONVERTIBLE_TO_JPEG, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension!) {
                            formatsToConvertToJPEG.toggle(format)
                            if formatsToConvertToJPEG.contains(format) {
                                formatsToConvertToPNG.remove(format)
                            }
                        }.buttonStyle(ToggleButton(isOn: .oneway { formatsToConvertToJPEG.contains(format) }))
                            .font(.mono(TextSize.subheadline))
                    }
                }
                HStack {
                    (Text("Convert to ").regular(TextSize.body) + Text("png").mono(TextSize.body)).padding(.trailing, Space.s)
                        .searchAnchor("images.compatibility.formatsToConvertToPNG")
                    Spacer()

                    ForEach(FORMATS_CONVERTIBLE_TO_PNG, id: \.identifier) { format in
                        Button(format.preferredFilenameExtension!) {
                            formatsToConvertToPNG.toggle(format)
                            if formatsToConvertToPNG.contains(format) {
                                formatsToConvertToJPEG.remove(format)
                            }
                        }.buttonStyle(ToggleButton(isOn: .oneway { formatsToConvertToPNG.contains(format) }))
                            .font(.mono(TextSize.subheadline))
                    }
                }
            }
            .id("compatibility")

        }
        .scrollContentBackground(.hidden)
        .padding(Space.xs)
    }
}

class BoundFormatter: Formatter {
    init(min: Int, max: Int) {
        self.max = max
        self.min = min
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    var min = 0
    var max = 0

    override func string(for obj: Any?) -> String? {
        guard let number = obj as? Int else {
            return nil
        }
        return String(number.capped(between: min, and: max))

    }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        guard let number = Int(string) else {
            return false
        }

        obj?.pointee = number.capped(between: min, and: max) as AnyObject

        return true
    }
}

let RESIZE_KEYS = SauceKey.NUMBER_KEYS.suffix(from: 1).arr

let keyEnv = EnvState()
struct KeysSettingsView: View {
    @Default(.enabledKeys) var enabledKeys
    @Default(.quickResizeKeys) var quickResizeKeys
    @Default(.keyComboModifiers) var keyComboModifiers

    var resizeKeys: some View {
        ForEach(RESIZE_KEYS, id: \.QWERTYKeyCode) { key in
            let number = key.character
            VStack(spacing: 1) {
                Button(number) {
                    quickResizeKeys = quickResizeKeys.contains(key)
                        ? quickResizeKeys.without(key)
                        : quickResizeKeys.with(key)
                }
                .buttonStyle(
                    ToggleButton(isOn: .oneway { quickResizeKeys.contains(key) })
                )
                Text("\(number)0%")
                    .mono(TextSize.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    var body: some View {
        Form {
            Section(header: SectionHeader(title: "Trigger keys")) {
                DirectionalModifierView(triggerKeys: $keyComboModifiers, showFnCaps: false, allowShiftAlone: false)
            }
            .searchAnchor("keys.triggerkeys.keyComboModifiers")
            Section(header: SectionHeader(title: "Action keys")) {
                keyToggle(.minus, actionName: "Downscale", description: "Decrease resolution of the last image or video")
                keyToggle(.x, actionName: "Speed up video", description: "Make video playback faster by dropping frames")
                keyToggle(.delete, actionName: "Stop and Dismiss", description: "Stop the last running action and dismiss the floating result")
                keyToggle(.escape, actionName: "Stop and Clear All", description: "Stop running optimisations and clear all floating results")
                keyToggle(.equal, actionName: "Bring Back", description: "Bring back the last removed floating result")
                keyToggle(.space, actionName: "Quick Look", description: "Preview the latest image or video")
                keyToggle(.r, actionName: "Rename", description: "Rename the file of the latest image or video")
                keyToggle(.z, actionName: "Restore original", description: "Revert optimisations and downscaling actions done on the latest image or video")
                keyToggle(.p, actionName: "Pause optimisations", description: "Pause or stop automatic optimisations")
                keyToggle(.c, actionName: "Optimise current clipboard", description: "Apply optimisations on the copied image, URL or path")
                keyToggle(.a, actionName: "Optimise aggressively", description: "Apply aggressive optimisations on the copied image, URL or path")
            }.padding(.leading, Space.xl)
                .searchAnchor("keys.actionkeys.enabledKeys")
            Section(header: SectionHeader(title: "Resize keys")) {
                HStack(alignment: .bottom, spacing: Space.s) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Hold the trigger keys and").round(TextSize.callout, weight: .regular)
                        Text("press a number to downscale to").mono(TextSize.caption).foregroundColor(.secondary)
                    }
                    VStack(spacing: 1) {
                        triggerKeyCap
                        // Kept for vertical alignment with the number keys' percentage labels, but hidden.
                        Text("hold").mono(TextSize.caption).foregroundColor(.secondary).hidden()
                    }
                    resizeKeys
                }.fixedSize()
            }.padding(.leading, Space.xl)
                .searchAnchor("keys.resizekeys.quickResizeKeys")
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity)
        .environmentObject(keyEnv)
    }

    /// A static key-cap rendering of the configured trigger modifiers, one separate cap per modifier (e.g.
    /// ⌃ ⇧), shown to the left of each action/resize key so it's obvious those modifiers must be held
    /// together with that key. Styled lighter than the action keys (secondary text, fainter fill) so it
    /// reads as the held prefix, not the key itself.
    var triggerKeyCap: some View {
        HStack(spacing: Space.xs) {
            ForEach(keyComboModifiers) { key in
                Text(key.str)
                    .font(.system(size: TextSize.title3, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, Space.xs)
                    .padding(.vertical, Space.xs)
                    .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
        }
    }

    @ViewBuilder
    func keyToggle(_ key: SauceKey, actionName: String, description: String) -> some View {
        let binding = Binding(
            get: { enabledKeys.contains(key) },
            set: { enabledKeys = $0 ? enabledKeys.with(key) : enabledKeys.without(key) }
        )
        Toggle(isOn: binding, label: {
            HStack {
                triggerKeyCap
                DynamicKey(key: .constant(key))
                    .font(.mono(TextSize.title3, weight: SauceKey.ALPHANUMERIC_KEYS.contains(key) ? .medium : .heavy))
                VStack(alignment: .leading, spacing: -1) {
                    Text(actionName)
                    Text(description).mono(TextSize.caption)
                }
            }
        })
        .accessibilityLabel(actionName)
        .accessibilityHint(description)
    }

}


func settingLabel(_ title: LocalizedStringKey, _ detail: LocalizedStringKey? = nil) -> Text {
    guard let detail else { return Text(title).regular(TextSize.body) }
    return Text(title).regular(TextSize.body)
        + Text("\n")
        + Text(detail).round(TextSize.subheadline, weight: .regular).foregroundColor(.secondary)
}

struct LegalNotice: View {
    var body: some View {
        Text("Based on Clop by The low-tech guys. Licensed under GPLv3, without any warranty.")
            .font(.mono(TextSize.subheadline, weight: .regular))
            .foregroundColor(.secondary)
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: Space.m) {
            SwiftUI.Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 128, height: 128)
            Text("Polc")
                .round(TextSize.display, weight: .black)
                .padding(.top, -4)
                .searchAnchor("about.about.version")
            Text("v\(Bundle.main.version)")
                .mono(TextSize.body, weight: .regular)
                .foregroundColor(.secondary)
            Link("Source", destination: "https://github.com/stephenangeloni/Clop".url!)
                .underline()
                .opacity(0.75)
                .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
        .fill()
    }
}

import SymbolPicker

struct IconPickerView: View {
    @Binding var icon: String

    var body: some View {
        Button {
            iconPickerPresented = true
        } label: {
            SwiftUI.Image(systemName: icon)
        }
        .accessibilityLabel("Icon")
        .sheet(isPresented: $iconPickerPresented) {
            // Keeps the category this picker has always opened on: the default became `all` in
            // SymbolPicker 2.1.0.
            SymbolPicker(symbol: $icon, initialCategories: ["cameraandphotos"])
        }
    }

    @State private var iconPickerPresented = false

}

struct ResultsSettingsView: View {
    @Default(.enableDragAndDrop) var enableDragAndDrop
    @Default(.onlyShowDropZoneOnOption) var onlyShowDropZoneOnOption
    @Default(.autoCopyToClipboard) var autoCopyToClipboard
    @Default(.floatingResultsCorner) var floatingResultsCorner
    @Default(.useBatchModeForFolders) var useBatchModeForFolders
    @Default(.batchModeFileCountThreshold) var batchModeFileCountThreshold

    @ObservedObject var svm = settingsViewManager

    var toggles: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Drop zone", subtitle: "Drag files, paths and URLs onto a global zone to optimise them")
            VStack(alignment: .leading, spacing: Space.s) {
                Toggle(isOn: $enableDragAndDrop) {
                    settingLabel("Enable drop zone", "Allows dragging files, paths and URLs to a global drop zone for optimisation")
                }
                .searchAnchor("dropzone.dropzone.enableDragAndDrop")
                Toggle(isOn: $onlyShowDropZoneOnOption) {
                    settingLabel("Require pressing ⌥ Option to show drop zone", "Hide drop zone by default to avoid distractions while dragging files, show it by manually pressing ⌥ Option once")
                }
                .padding(.leading, Space.xl)
                .disabled(!enableDragAndDrop)
                .searchAnchor("dropzone.dropzone.onlyShowDropZoneOnOption")
                Toggle(isOn: $autoCopyToClipboard) {
                    settingLabel("Auto Copy optimised files to clipboard", "Copy files resulting from drop zone or file watch optimisation\nso they can be pasted right after optimisation ends")
                }
                .searchAnchor("dropzone.dropzone.autoCopyToClipboard")
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
        }
    }

    var preview: some View {
        VStack(spacing: Space.s) {
            DropZoneView()
                .disabled(!enableDragAndDrop)
                .saturation(enableDragAndDrop ? 1 : 0.5)
                .preview(true)
                .padding(Space.xs)
                .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(Color.gray.opacity(0.2), lineWidth: 2))
                .fixedSize()

            Text("Drag files onto the drop zone\nto optimise them")
                .font(.system(size: TextSize.callout))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            dropZonePage
                .onChange(of: svm.editingPresetZoneID) { id in
                    guard let id else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation { proxy.scrollTo("editor-\(id)", anchor: .center) }
                    }
                }
        }
    }

    var dropZonePage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(alignment: .center, spacing: Space.xl) {
                    toggles
                    Spacer()
                    preview
                }
                .frame(height: 250)
                .padding(.horizontal)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)

                Divider()

                PresetZonesSection()
                    .padding(.horizontal, Space.l)
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                    .id("presetZones")

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Batch mode", subtitle: "Process a large drop in a fast native window instead of one floating result per file")
                    VStack(alignment: .leading, spacing: Space.s) {
                        Toggle(isOn: $useBatchModeForFolders) {
                            settingLabel("Use batch mode for large drops", "Dropping many files at once (or a folder with many files) opens a single batch window that optimises them all efficiently. Originals are backed up first and can be restored.")
                        }
                        .searchAnchor("dropzone.batchmode.useBatchModeForFolders")
                        HStack {
                            Text("Switch to batch mode when dropping more than").regular(TextSize.body)
                            Spacer()
                            TextField("", value: $batchModeFileCountThreshold, format: .number)
                                .accessibilityLabel("Switch to batch mode when dropping more than")
                                .multilineTextAlignment(.center)
                                .font(.mono(TextSize.callout))
                                .frame(width: 60)
                                .searchAnchor("dropzone.batchmode.batchModeFileCountThreshold", namesControl: true)
                            Text("files").regular(TextSize.body)
                        }
                        .disabled(!useBatchModeForFolders)
                        .opacity(useBatchModeForFolders ? 1 : 0.6)
                    }
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.s)
                }
                .padding(.horizontal, Space.l)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Automation", subtitle: "Run actions on files dropped here: convert, crop, copy, rename and more")
                    SourceAutomationsSection(source: .dropZone)
                        .disabled(!enableDragAndDrop)
                        .padding(.bottom, Space.s)
                }
                .padding(.horizontal, Space.l)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
                .id("automation")

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Floating results", subtitle: "The thumbnail, progress and actions shown for each optimised file")
                    FloatingSettingsView()
                }
                .padding(.horizontal, Space.l)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
            .padding(.top)
        }
        .hfill()
        .scrollsToAutomation()
    }
}

struct PresetZonesSection: View {
    @Default(.enableDragAndDrop) var enableDragAndDrop
    @Default(.onlyShowPresetZonesOnControlTapped) var onlyShowPresetZonesOnControlTapped
    @Default(.presetZones) var presetZones

    @ObservedObject var svm = settingsViewManager

    var previews: some View {
        Grid(horizontalSpacing: Space.l, verticalSpacing: Space.m) {
            GridRow {
                zonePreview(.image)
                zonePreview(.video)
            }
            GridRow {
                zonePreview(.audio)
                zonePreview(.pdf)
            }
        }
        .hfill()
        .padding(.vertical, Space.xs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Preset zones", subtitle: "Hold or tap ⌃ Control while dragging to show a zone per file type. Click a zone to assign or create a pipeline.")
            VStack(alignment: .leading, spacing: Space.s) {
                Picker("Show preset zones by holding or tapping the **⌃ Control** key", selection: $onlyShowPresetZonesOnControlTapped) {
                    Text("Hold").tag(false)
                    Text("Tap").tag(true)
                }
                .pickerStyle(.segmented)
                .searchAnchor("presetZones.showingpresetzones.onlyShowPresetZonesOnControlTapped")

                previews
                    .searchAnchor("presetZones.presetzones.presetZones")

                if let id = svm.editingPresetZoneID, let zone = presetZones.first(where: { $0.id == id }) {
                    PresetZoneRow(zone: zone) { svm.editingPresetZoneID = nil }
                        .id("editor-\(id)")
                        .padding(.top, Space.xs)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
        }
        .disabled(!enableDragAndDrop)
        .saturation(enableDragAndDrop ? 1 : 0.5)
    }

    func zonePreview(_ type: PolcFileType) -> some View {
        VStack(spacing: Space.xs) {
            DropZoneView(presetFileType: type)
                .preview(true)
            HStack(spacing: Space.xs) {
                SwiftUI.Image(systemName: type.symbolName)
                Text(typeName(type))
            }
            .font(.system(size: TextSize.body, weight: .semibold))
            .foregroundColor(type.color)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(Capsule().fill(type.color.opacity(0.15)))
            .padding(.top, 1)
        }
    }

    func typeName(_ t: PolcFileType) -> String {
        t == .pdf ? "PDF" : t.description.capitalized
    }

}

struct FloatingSettingsView: View {
    @Default(.enableFloatingResults) var enableFloatingResults
    @Default(.showCompactImages) var showCompactImages
    @Default(.autoHideFloatingResults) var autoHideFloatingResults
    @Default(.autoHideFloatingResultsAfter) var autoHideFloatingResultsAfter
    @Default(.autoHideClipboardResultAfter) var autoHideClipboardResultAfter
    @Default(.autoClearAllCompactResultsAfter) var autoClearAllCompactResultsAfter
    @Default(.floatingResultsCorner) var floatingResultsCorner
    @Default(.alwaysShowCompactResults) var alwaysShowCompactResults
    @Default(.hideFloatingResultTooltips) var hideFloatingResultTooltips
    @Default(.floatingResultActions) var floatingResultActions
    @Default(.compactResultActions) var compactResultActions
    @Default(.formatPickerStyle) var formatPickerStyle
    @Default(.followCursorScreen) var followCursorScreen
    @Default(.showCopyClearButtons) var showCopyClearButtons

    @Default(.dismissFloatingResultOnDrop) var dismissFloatingResultOnDrop
    @Default(.dismissFloatingResultOnUpload) var dismissFloatingResultOnUpload
    @Default(.dismissCompactResultOnDrop) var dismissCompactResultOnDrop
    @Default(.dismissCompactResultOnUpload) var dismissCompactResultOnUpload

    @State var compact = SWIFTUI_PREVIEW

    var settings: some View {
        Form {
            Toggle(isOn: $enableFloatingResults) {
                Text("Show floating results").regular(TextSize.body)
                    + Text("\n\nDisabling this will make Polc run in an UI-less mode, but keep optimising files in the background. Drop zone can be disabled separately in the Drop zone section above")
                    .round(TextSize.caption, weight: .regular)
                    .foregroundColor(.secondary)
            }
            .searchAnchor("floating.main.enableFloatingResults", namesControl: true)
            Section(header: SectionHeader(title: "Layout")) {
                Picker("Position on screen", selection: $floatingResultsCorner) {
                    Text("Bottom right").tag(ScreenCorner.bottomRight)
                    Text("Bottom left").tag(ScreenCorner.bottomLeft)
                    Text("Top right").tag(ScreenCorner.topRight)
                    Text("Top left").tag(ScreenCorner.topLeft)
                }
                .searchAnchor("floating.layout.floatingResultsCorner", namesControl: true)
                Toggle(isOn: $followCursorScreen) {
                    Text("Follow the cursor across screens").regular(TextSize.body)
                        + Text("\n\nWhen the cursor stays on another screen for a couple of seconds, move the results to that screen")
                        .round(TextSize.caption, weight: .regular)
                        .foregroundColor(.secondary)
                }
                .searchAnchor("floating.layout.followCursorScreen", namesControl: true)
                Toggle(isOn: $hideFloatingResultTooltips) {
                    Text("Hide button tooltips").regular(TextSize.body)
                        + Text("\n\nDon't show the action name labels that pop up while hovering result buttons")
                        .round(TextSize.caption, weight: .regular)
                        .foregroundColor(.secondary)
                }
                .searchAnchor("floating.layout.hideFloatingResultTooltips", namesControl: true)
                Toggle(isOn: $alwaysShowCompactResults) {
                    Text("Always use compact layout").regular(TextSize.body)
                        + Text("\n\nBy default, the layout switches to compact automatically when there are more than 5 results on the screen")
                        .round(TextSize.caption, weight: .regular)
                        .foregroundColor(.secondary)
                }
                .searchAnchor("floating.layout.alwaysShowCompactResults", namesControl: true)
            }.disabled(!enableFloatingResults)

            Section(header: SectionHeader(title: "Full layout")) {
                // Subtitle sits under both the label and the picker so it can wrap across the whole
                // row width instead of being squeezed into the label column by the picker.
                VStack(alignment: .leading, spacing: Space.xs) {
                    Picker(selection: $formatPickerStyle) {
                        Text("format bar at the bottom").tag(FormatPickerStyle.bar)
                        Text("hover on the file extension").tag(FormatPickerStyle.extensionHover)
                    } label: {
                        Text("Change format by").regular(TextSize.body)
                    }
                    .searchAnchor("floating.fulllayout.formatPickerStyle", namesControl: true)
                    Text("The format bar shows all convertible formats as one-click segments at the bottom of the result; the extension chip pops the formats up on hover")
                        .round(TextSize.caption, weight: .regular)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Show Copy all / Clear all buttons", isOn: $showCopyClearButtons)
                    .searchAnchor("floating.fulllayout.showCopyClearButtons", namesControl: true)
                Text("Dismiss result after")
                Toggle("drag and drop outside", isOn: $dismissFloatingResultOnDrop).padding(.leading, Space.xl)
                    .searchAnchor("floating.fulllayout.dismissFloatingResultOnDrop", namesControl: true)
                Toggle("upload to Dropshare", isOn: $dismissFloatingResultOnUpload).padding(.leading, Space.xl)
                    .searchAnchor("floating.fulllayout.dismissFloatingResultOnUpload", namesControl: true)

                Toggle("Auto hide", isOn: $autoHideFloatingResults)
                    .searchAnchor("floating.fulllayout.autoHideFloatingResults", namesControl: true)
                Picker("files after", selection: $autoHideFloatingResultsAfter) {
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("never").tag(0)
                }.disabled(!autoHideFloatingResults).padding(.leading, Space.xl)
                    .searchAnchor("floating.fulllayout.autoHideFloatingResultsAfter", namesControl: true)
                Picker("clipboard after", selection: $autoHideClipboardResultAfter) {
                    Text("1 seconds").tag(1)
                    Text("2 seconds").tag(2)
                    Text("3 seconds").tag(3)
                    Text("4 seconds").tag(4)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("same as non-clipboard").tag(-1)
                    Text("never").tag(0)
                }.disabled(!autoHideFloatingResults).padding(.leading, Space.xl)
                    .searchAnchor("floating.fulllayout.autoHideClipboardResultAfter", namesControl: true)
            }.disabled(!enableFloatingResults)

            Section(header: SectionHeader(title: "Compact layout")) {
                Toggle("Show images", isOn: $showCompactImages)
                    .searchAnchor("floating.compactlayout.showCompactImages", namesControl: true)
                Text("Dismiss result after")
                Toggle("drag and drop outside", isOn: $dismissCompactResultOnDrop).padding(.leading, Space.xl)
                    .searchAnchor("floating.compactlayout.dismissCompactResultOnDrop", namesControl: true)
                Toggle("upload to Dropshare", isOn: $dismissCompactResultOnUpload).padding(.leading, Space.xl)
                    .searchAnchor("floating.compactlayout.dismissCompactResultOnUpload", namesControl: true)

                Picker("Auto clear all after", selection: $autoClearAllCompactResultsAfter) {
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("30 minutes").tag(1800)
                    Text("never").tag(0)
                }
                .searchAnchor("floating.compactlayout.autoClearAllCompactResultsAfter", namesControl: true)
            }.disabled(!enableFloatingResults)

        }
        .scrollContentBackground(.hidden)
        // idealWidth keeps the window's fit-to-content width at the old 380pt: without it, the long
        // multiline labels report their unwrapped single-line width as ideal and the pane demands
        // ~1100px. No minWidth so a narrow window squeezes the form instead of clipping it.
        .frame(idealWidth: 380, maxWidth: .infinity)
    }

    var body: some View {
        HStack(alignment: .top) {
            settings

            VStack {
                if compact {
                    CompactPreview()
                        .frame(width: THUMB_SIZE.width + 60, height: 550, alignment: .center)
                        .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(Color.gray.opacity(0.2), lineWidth: 2))
                        .disabled(!enableFloatingResults)
                        .saturation(enableFloatingResults ? 1 : 0.5)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                FloatingPreview()
                                // Anchor pinned to the very bottom of the list so we can scroll the
                                // "Clear all" / "Copy all" buttons into view by default.
                                Color.clear.frame(height: 1).id("previewBottom")
                            }
                        }
                        .frame(width: THUMB_SIZE.width + 60, height: 550)
                        .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(Color.gray.opacity(0.2), lineWidth: 2))
                        .disabled(!enableFloatingResults)
                        .saturation(enableFloatingResults ? 1 : 0.5)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy.scrollTo("previewBottom", anchor: .bottom)
                            }
                        }
                    }
                }
                Picker("Layout", selection: $compact) {
                    Text("Compact").tag(true)
                    Text("Full").tag(false)
                }.pickerStyle(.segmented).frame(width: 200)
                    .labelsHidden()
                Text("only for preview")
                    .round(TextSize.caption)
                    .foregroundColor(.secondary)

                Divider().frame(width: 100).padding(.vertical, Space.xs)

                if compact {
                    ActionListPicker(label: "Side actions", vertical: false, actions: $compactResultActions)
                        .searchAnchor("floating.main.compactResultActions")
                } else {
                    FloatingActionGridPicker(actions: $floatingResultActions)
                }
            }
            // The flexible form eats all leftover width, so the preview column needs its own
            // breathing room from the window's right edge.
            .padding(.trailing)
        }
        .hfill()
        .padding(.top)
        .onAppear {
            compact = alwaysShowCompactResults
            // Materialise the preview sample files only now that this tab is on screen.
            FloatingPreview.materializeSamples()
            CompactPreview.materializeSamples()
        }
        .onChange(of: alwaysShowCompactResults) { value in
            compact = value
        }
    }
}
/// One row of the "Edit with external app" settings: shows the chosen app (icon + name) for a file
/// type, or a "Choose app…" button. Any app can be picked; nothing is filtered.
struct EditorAppRow: View {
    let label: String
    let systemImage: String
    let key: Defaults.Key<String>

    var body: some View {
        HStack {
            SwiftUI.Image(systemName: systemImage).foregroundColor(.secondary).frame(width: 20)
            Text(label)
            Spacer()
            if !appPath.isEmpty, FileManager.default.fileExists(atPath: appPath) {
                let url = URL(fileURLWithPath: appPath)
                Button(action: pick) {
                    SwiftUI.Image(nsImage: appIcon(url))
                    Text(appName(url))
                }
                Button(action: clear) {
                    SwiftUI.Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove")
                .accessibilityLabel("Remove")
            } else {
                Button("Choose app…", action: pick)
            }
        }
        .onAppear { appPath = Defaults[key].resolvedPath }
    }

    @State private var appPath = ""

    private func appIcon(_ url: URL) -> NSImage {
        let i = NSWorkspace.shared.icon(forFile: url.path)
        i.size = NSSize(width: 16, height: 16)
        return i
    }

    private func appName(_ url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.deletingPathExtension().lastPathComponent
    }

    private func clear() {
        appPath = ""
        Defaults[key] = ""
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        panel.message = "Choose an app to edit \(label.lowercased()) with"
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            appPath = url.path
            Defaults[key] = url.path.portablePath
        }
    }
}

struct ClipboardSettingsView: View {
    @Default(.optimiseTIFF) var optimiseTIFF
    @Default(.optimiseHEICAVIFClipboard) var optimiseHEICAVIFClipboard
    @Default(.optimiseVideoClipboard) var optimiseVideoClipboard
    @Default(.optimiseAudioClipboard) var optimiseAudioClipboard
    @Default(.optimisePDFClipboard) var optimisePDFClipboard
    @Default(.optimiseImagePathClipboard) var optimiseImagePathClipboard
    @Default(.enableClipboardOptimiser) var enableClipboardOptimiser
    @Default(.clipboardIgnoredAppBundleIds) var clipboardIgnoredAppBundleIds
    @Default(.appendClipboardResults) var appendClipboardResults
    @Default(.copyConsecutiveClipboardImages) var copyConsecutiveClipboardImages
    @Default(.clipboardAccumulationTimeout) var clipboardAccumulationTimeout

    var disabledClipboardTypes: Set<PolcFileType> {
        guard enableClipboardOptimiser else { return Set(PolcFileType.allCases) }
        var disabled: Set<PolcFileType> = []
        if !optimiseVideoClipboard {
            disabled.insert(.video)
        }
        if !optimiseAudioClipboard {
            disabled.insert(.audio)
        }
        if !optimisePDFClipboard {
            disabled.insert(.pdf)
        }
        return disabled
    }

    var body: some View {
        Form {
            Section(header: SectionHeader(title: "Clipboard", subtitle: "Watch for copied data and optimise it automatically")) {
                Toggle(isOn: $enableClipboardOptimiser) {
                    settingLabel("Enable clipboard optimiser", "Watch for copied data and optimise it automatically")
                }
                .searchAnchor("clipboard.clipboard.enableClipboardOptimiser", namesControl: true)
                Group {
                    Toggle(isOn: .constant(true)) {
                        settingLabel("Image data", "Copied image data (e.g. screenshots)")
                    }.disabled(true)
                        .accessibilityLabel("Image data")
                    Toggle(isOn: $optimiseTIFF) {
                        settingLabel("TIFF data", "Usually from graphical design apps, sometimes better left alone")
                    }
                    .searchAnchor("clipboard.clipboard.optimiseTIFF", namesControl: true)
                    Toggle(isOn: $optimiseHEICAVIFClipboard) {
                        Text("HEIC and AVIF data").regular(TextSize.body)
                    }
                    .searchAnchor("clipboard.clipboard.optimiseHEICAVIFClipboard", namesControl: true)
                    Toggle(isOn: $optimiseImagePathClipboard) {
                        settingLabel("Image files", "Copying images from Finder results in file paths instead of image data")
                    }
                    .searchAnchor("clipboard.clipboard.optimiseImagePathClipboard", namesControl: true)
                    Toggle(isOn: $optimiseVideoClipboard) {
                        settingLabel("Video files", "Optimise copied video file paths")
                    }
                    .searchAnchor("clipboard.clipboard.optimiseVideoClipboard", namesControl: true)
                    Toggle(isOn: $optimiseAudioClipboard) {
                        settingLabel("Audio files", "Optimise copied audio file paths")
                    }
                    .searchAnchor("clipboard.clipboard.optimiseAudioClipboard", namesControl: true)
                    Toggle(isOn: $optimisePDFClipboard) {
                        settingLabel("PDF files", "Optimise copied PDF file paths")
                    }
                    .searchAnchor("clipboard.clipboard.optimisePDFClipboard", namesControl: true)
                }
                .disabled(!enableClipboardOptimiser)
                .padding(.leading, Space.xl)

                Toggle(isOn: $appendClipboardResults) {
                    settingLabel("Keep all clipboard results", "Show each clipboard optimisation as a separate result instead of replacing the previous one")
                }.disabled(!enableClipboardOptimiser)
                    .searchAnchor("clipboard.clipboard.appendClipboardResults", namesControl: true)
                if appendClipboardResults {
                    Toggle(isOn: $copyConsecutiveClipboardImages) {
                        Text("Accumulate optimised images in clipboard").regular(TextSize.body)
                            + Text("\nEach new optimised image is added to a file list in the clipboard, so you can paste them all at once into image editor apps like Pixelmator or Affinity, or into notes").round(TextSize.subheadline, weight: .regular)
                            .foregroundColor(.secondary)
                    }
                    .disabled(!enableClipboardOptimiser)
                    .padding(.leading, Space.xl)
                    .searchAnchor("clipboard.clipboard.copyConsecutiveClipboardImages", namesControl: true)

                    HStack {
                        Text("Reset after").regular(TextSize.body)
                        Picker("Reset after", selection: $clipboardAccumulationTimeout) {
                            Text("10 seconds").tag(10)
                            Text("30 seconds").tag(30)
                            Text("1 minute").tag(60)
                            Text("2 minutes").tag(120)
                            Text("5 minutes").tag(300)
                            Text("Never").tag(0)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .searchAnchor("clipboard.clipboard.clipboardAccumulationTimeout")
                        Text("of inactivity").regular(TextSize.body)
                    }
                    .padding(.leading, Space.xl)
                }
            }

            Section(header: SectionHeader(title: "Ignored apps", subtitle: "Skip clipboard optimisation while one of these apps is in front")) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    IgnoredAppsPicker(bundleIds: $clipboardIgnoredAppBundleIds, enabled: enableClipboardOptimiser)
                        .padding(.top, Space.xs)
                        .searchAnchor("clipboard.ignoredapps.clipboardIgnoredAppBundleIds")
                }
                .disabled(!enableClipboardOptimiser)
                .opacity(enableClipboardOptimiser ? 1 : 0.6)
            }
            .searchAnchor("clipboard.ignoredapps.clipboardIgnoredAppBundleIds")

            Section(header: SectionHeader(title: "Automation", subtitle: "Run actions on every file you copy")) {
                SourceAutomationsSection(source: .clipboard, disabledTypes: disabledClipboardTypes)
            }
            .id("automation")
        }
        .scrollContentBackground(.hidden)
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, Space.xl)
        .scrollsToAutomation()
    }
}

struct GeneralSettingsView: View {
    enum MenubarIconStyle { case new, geometric, classic, hidden }

    static let menubarIconNew = templatedMenubarIcon("MenubarIcon")
    static let menubarIconGeometric = templatedMenubarIcon("MenubarIconGeometric")
    static let menubarIconClassic = templatedMenubarIcon("MenubarIconClassic")

    @Default(.showMenubarIcon) var showMenubarIcon
    @Default(.useClassicMenubarIcon) var useClassicMenubarIcon
    @Default(.useGeometricMenubarIcon) var useGeometricMenubarIcon
    @Default(.stripMetadata) var stripMetadata
    @Default(.preserveColorMetadata) var preserveColorMetadata
    @Default(.preserveDates) var preserveDates
    @Default(.optimisedFileProtectionMs) var optimisedFileProtectionMs

    @Default(.workdir) var workdir
    @Default(.workdirCleanupInterval) var workdirCleanupInterval

    var workdirBinding: Binding<String> {
        Binding(
            get: { workdir.shellString },
            set: { value in
                guard !value.isEmpty, let path = value.resolvedPath.existingFilePath else {
                    return
                }
                workdir = path.portablePath
            }
        )
    }

    /// Maps the four-way picker onto the stored bools: the icon choice only touches the
    /// style bools so the new/geometric/classic preference is remembered while hidden.
    /// `useGeometricMenubarIcon` takes precedence over `useClassicMenubarIcon`.
    var menubarIconStyle: Binding<MenubarIconStyle> {
        Binding(
            get: {
                guard showMenubarIcon else { return .hidden }
                if useGeometricMenubarIcon {
                    return .geometric
                }
                return useClassicMenubarIcon ? .classic : .new
            },
            set: { style in
                showMenubarIcon = style != .hidden
                if style != .hidden {
                    useClassicMenubarIcon = style == .classic
                    useGeometricMenubarIcon = style == .geometric
                }
            }
        )
    }

    var body: some View {
        Form {
            HStack {
                Text("Menubar icon")
                    .searchAnchor("general.main.showMenubarIcon")
                Spacer()
                menubarIconButton(.new) { SwiftUI.Image(nsImage: Self.menubarIconNew).resizable() }
                menubarIconButton(.geometric) { SwiftUI.Image(nsImage: Self.menubarIconGeometric).resizable() }
                menubarIconButton(.classic) { SwiftUI.Image(nsImage: Self.menubarIconClassic).resizable() }
                menubarIconButton(.hidden) { SwiftUI.Image(systemName: "eye.slash").resizable() }
            }
            LaunchAtLogin.Toggle()
                .accessibilityLabel("Launch at login")

            Section(header: SectionHeader(title: "Edit with external app", subtitle: "Hand an optimised file to an editor of your choice with ⌘E or the right-click menu")) {
                EditorAppRow(label: "Images", systemImage: "photo", key: .editorAppImage)
                    .searchAnchor("general.editwithexternalapp.editorAppImage")
                EditorAppRow(label: "Videos", systemImage: "video", key: .editorAppVideo)
                    .searchAnchor("general.editwithexternalapp.editorAppVideo")
                EditorAppRow(label: "Audio", systemImage: "waveform", key: .editorAppAudio)
                    .searchAnchor("general.editwithexternalapp.editorAppAudio")
                EditorAppRow(label: "PDFs", systemImage: "doc", key: .editorAppPDF)
                    .searchAnchor("general.editwithexternalapp.editorAppPDF")
            }

            Section(header: SectionHeader(title: "Working directory", subtitle: "Where temporary files and backups are stored and where the optimised files are saved")) {
                HStack {
                    Text("Path").regular(TextSize.body).padding(.trailing, Space.s)
                        .searchAnchor("general.workingdirectory.workdir")
                    TextField("", text: workdirBinding)
                        .accessibilityLabel("Working directory")
                        .multilineTextAlignment(.center)
                        .font(.mono(TextSize.callout))
                        .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).stroke(Color.gray, lineWidth: 1).scaleEffect(y: TEXT_FIELD_SCALE).offset(x: TEXT_FIELD_OFFSET))
                    Button("Reset") {
                        workdir = Defaults.Keys.workdir.defaultValue
                    }
                    .buttonStyle(.bordered)
                    .font(.regular(TextSize.subheadline))
                }

                Picker("Periodically cleanup files older than", selection: $workdirCleanupInterval) {
                    Text("10 minutes").tag(CleanupInterval.every10Minutes)
                    Text("1 hour").tag(CleanupInterval.hourly)
                    Text("12 hours").tag(CleanupInterval.every12Hours)
                    Text("1 day").tag(CleanupInterval.daily)
                    Text("3 days").tag(CleanupInterval.every3Days)
                    Text("1 week").tag(CleanupInterval.weekly)
                    Text("1 month").tag(CleanupInterval.monthly)
                    Text("never clean up").tag(CleanupInterval.never)
                }
                .searchAnchor("general.workingdirectory.workdirCleanupInterval", namesControl: true)
            }

            Section(header: SectionHeader(title: "Optimisation")) {
                Toggle(isOn: $stripMetadata) {
                    settingLabel("Strip EXIF Metadata", "Deleted identifiable metadata from files (e.g. camera that took the photo, location, date and time etc.)")
                }
                .searchAnchor("general.optimisation.stripMetadata", namesControl: true)
                Toggle(isOn: $preserveColorMetadata) {
                    settingLabel("Preserve color profile metadata", "Keep color profile metadata tags untouched when stripping EXIF metadata")
                }
                .padding(.leading, Space.xl)
                .disabled(!stripMetadata)
                .searchAnchor("general.optimisation.preserveColorMetadata", namesControl: true)

                Toggle(isOn: $preserveDates) {
                    settingLabel("Preserve file creation and modification dates", "The optimised file will have the same creation and modification dates as the original file")
                }
                .searchAnchor("general.optimisation.preserveDates", namesControl: true)

                Picker(selection: $optimisedFileProtectionMs) {
                    Text("3 seconds").tag(3000)
                    Text("10 seconds").tag(10000)
                    Text("30 seconds").tag(30000)
                    Text("60 seconds").tag(60000)
                } label: {
                    settingLabel("Re-optimisation loop detection window", "Increase if files on iCloud Drive get optimised twice")
                }
                .searchAnchor("general.optimisation.optimisedFileProtectionMs", namesControl: true)
            }
        }
        .scrollContentBackground(.hidden)
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, Space.xl)
    }

    @ViewBuilder
    func menubarIconButton(_ style: MenubarIconStyle, @ViewBuilder icon: () -> some View) -> some View {
        let selected = menubarIconStyle.wrappedValue == style
        Button {
            menubarIconStyle.wrappedValue = style
        } label: {
            icon()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .frame(width: 46, height: 28)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .strokeBorder(selected ? Color.clear : Color.primary.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel({
            switch style {
            case .hidden: "Hidden"
            case .classic: "Classic"
            case .geometric: "Geometric"
            case .new: "New"
            }
        }())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help({
            switch style {
            case .hidden: "Hide the menubar icon"
            case .classic: "Use the classic menubar icon"
            case .geometric: "Use the geometric menubar icon"
            case .new: "Use the new menubar icon"
            }
        }())
    }

    /// Copy the menubar asset, mark it as a template and size it down so it tints and fits the picker buttons.
    static func templatedMenubarIcon(_ name: String) -> NSImage {
        guard let icon = NSImage(named: name)?.copy() as? NSImage else {
            return NSImage(size: NSSize(width: 18, height: 18))
        }
        icon.isTemplate = true
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }

}

struct HighlightedFolderRequest: Equatable {
    let fileType: PolcFileType
    let folder: String
}

class SettingsViewManager: ObservableObject {
    @Published var tab: SettingsView.Tabs = SWIFTUI_PREVIEW ? .results : .general
    @Published var searchQuery = ""
    /// The entry id a search result asked to jump to. See `SettingsSearchAnchor`.
    @Published var highlightedEntry: String? = nil
    @Published var windowOpen = false
    @Published var scrollToFileType: PolcFileType?
    /// Set by the "Configured in Compatibility" link in File Handling to scroll the destination
    /// tab down to its Compatibility section. Cleared once that section has reacted.
    @Published var scrollToCompatibility = false
    /// Set by an assignment pill's "Go to" (clipboard / drop zone) to scroll the destination tab down
    /// to its Automation section. Cleared once that section has reacted.
    @Published var scrollToAutomation = false
    @Published var highlightFolder: HighlightedFolderRequest?
    /// Set by a preset-zone menu in the inline preview to open (and scroll to) that zone's editor row in
    /// the same Results tab. Cleared once the row has reacted.
    @Published var editingPresetZoneID: String?
    /// Set by a floating result's "Pipeline: …" context-menu entry to open the Pipelines tab, scroll to
    /// the saved pipeline that ran on it and flash a highlight border. Cleared once the row has reacted.
    @Published var highlightPipelineID: String?
}

let settingsViewManager = SettingsViewManager()

struct HideSidebarToggleIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

struct SettingsSidebarRow: View {
    let tab: SettingsView.Tabs

    var body: some View {
        NavigationLink(value: tab) {
            Label {
                Text(tab.title)
            } icon: {
                SidebarIcon(symbol: tab.symbol, hue: tab.hue)
            }
        }
        .accessibilityIdentifier("settings.sidebar.\(tab)")
    }
}

struct SettingsView: View {
    enum Tabs: Int, Hashable, CaseIterable, Identifiable {
        case general, clipboard, files, video, audio, images, pdf, results, keys, pipelines, mcp, about

        var id: Int {
            rawValue
        }

        var next: Tabs {
            Tabs(rawValue: rawValue + 1) ?? .general
        }

        var previous: Tabs {
            Tabs(rawValue: rawValue - 1) ?? .about
        }

        var title: String {
            switch self {
            case .general: "General"
            case .clipboard: "Clipboard"
            case .files: "File handling"
            case .video: "Video"
            case .audio: "Audio"
            case .images: "Images"
            case .pdf: "PDF"
            case .results: "Results"
            case .keys: "Keyboard Shortcuts"
            case .pipelines: "Pipelines"
            case .mcp: "MCP"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .clipboard: "doc.on.clipboard"
            case .files: "folder.badge.gearshape"
            case .video: "video"
            case .audio: "waveform"
            case .images: "photo"
            case .pdf: "doc"
            case .results: "rectangle.stack"
            case .keys: "command.square"
            case .pipelines: "arrow.triangle.branch"
            case .mcp: "sparkles"
            case .about: "info.circle"
            }
        }

        var hue: SidebarHue {
            switch self {
            case .general: .stone
            case .clipboard: .dustyBlue
            case .files: .skin
            case .video: SidebarHue(light: Palette.video, dark: Palette.video)
            case .audio: SidebarHue(light: Palette.audio, dark: Palette.audio)
            case .images: SidebarHue(light: Palette.image, dark: Palette.image)
            case .pdf: SidebarHue(light: Palette.pdf, dark: Palette.pdf)
            case .results: .ochre
            case .keys: .violet
            case .pipelines: .orchid
            case .mcp: .mutedTeal
            case .about: .plum
            }
        }
    }

    static let topTabs: [Tabs] = [.general, .clipboard, .files]
    static let fileTypeTabs: [Tabs] = [.video, .audio, .images, .pdf]
    static let dropTabs: [Tabs] = [.results]
    static let automationTabs: [Tabs] = [.keys, .pipelines, .mcp]
    static let supportTabs: [Tabs] = [.about]

    @ObservedObject var svm = settingsViewManager

    @FocusState var searchFocused: Bool

    var body: some View {
        if svm.windowOpen {
            settings
        }
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            searchField
            Group {
                if svm.searchQuery.isEmpty {
                    tabList
                } else {
                    searchResults
                }
            }
            .listStyle(.sidebar)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        .modifier(HideSidebarToggleIfAvailable())
    }

    /// Polc's own field instead of `.searchable`, so `⌘F` can put the cursor in it: focusing a
    /// `.searchable` field from code needs macOS 15 and Polc runs on 13. rcmd's Settings window has
    /// the same field for the same reason.
    var searchField: some View {
        HStack(spacing: Space.xs) {
            // `SwiftUI.Image` qualified: Polc has its own `Image` type for optimisable files.
            SwiftUI.Image(systemName: "magnifyingglass")
                .font(.system(size: TextSize.callout, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search settings", text: $svm.searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                // The placeholder is not a name: without this the field is announced as nothing.
                .accessibilityLabel("Search settings")
            if !svm.searchQuery.isEmpty {
                Button { svm.searchQuery = "" } label: {
                    SwiftUI.Image(systemName: "xmark.circle.fill")
                        .font(.system(size: TextSize.callout))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(.quaternary))
        .padding(.horizontal, Space.s)
        .padding(.top, Space.s)
        .padding(.bottom, Space.xs)
        .onExitCommand { svm.searchQuery = "" }
    }

    /// What the search field finds, in place of the tab list.
    ///
    /// The row carries its pane and section so the answer is often readable without going anywhere,
    /// and selecting it opens that pane. The index behind this is the same one the MCP server reads,
    /// so a question typed here and a question asked of an agent land on the same row.
    @ViewBuilder var searchResults: some View {
        let results = SettingsSearchIndex.search(svm.searchQuery)
        if results.isEmpty {
            List {
                Text("Nothing matches \"\(svm.searchQuery)\"")
                    .round(TextSize.callout)
                    .foregroundColor(.secondary)
            }
        } else {
            List {
                ForEach(results) { entry in
                    Button(action: { svm.jump(to: entry) }) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(entry.title).medium(TextSize.callout)
                            if !entry.subtitle.isEmpty {
                                Text(entry.subtitle)
                                    .round(TextSize.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            Text([entry.tab.title, entry.section].filter { !$0.isEmpty }.joined(separator: " › "))
                                .round(TextSize.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Copy deep link") {
                            let link = SettingsURL.link(to: entry)
                            withGeneralPasteboard { pb in
                                pb.clearContents()
                                pb.setString(link, forType: .string)
                            }
                        }
                    }
                }
            }
        }
    }

    var tabList: some View {
        List(selection: $svm.tab) {
            ForEach(Self.topTabs, id: \.self) { tab in
                SettingsSidebarRow(tab: tab)
            }
            Section("File types") {
                ForEach(Self.fileTypeTabs, id: \.self) { tab in
                    SettingsSidebarRow(tab: tab)
                }
            }
            Section("Drops & Results") {
                ForEach(Self.dropTabs, id: \.self) { tab in
                    SettingsSidebarRow(tab: tab)
                }
            }
            Section("Shortcuts & Automation") {
                ForEach(Self.automationTabs, id: \.self) { tab in
                    SettingsSidebarRow(tab: tab)
                }
            }
            Section("Support") {
                ForEach(Self.supportTabs, id: \.self) { tab in
                    SettingsSidebarRow(tab: tab)
                }
            }
        }
    }

    var settings: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            SettingsPaneScroller { detailView }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Keep the window's title as "Settings" so it exists for the Window menu,
                // accessibility and Mission Control. `.windowStyle(.hiddenTitleBar)` keeps it
                // from being drawn in the titlebar. Using the tab name here (as before) leaked
                // the selected tab into the window title.
                .navigationTitle("Settings")
                .background(PreventSidebarCollapse())
        }
        .navigationSplitViewStyle(.balanced)
        .formStyle(.grouped)
        .background {
            // ⌘F puts the cursor in the sidebar's search field from anywhere in Settings. A hidden
            // button is how a shortcut reaches a `@FocusState` without a menu command.
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notif in
            guard !SWIFTUI_PREVIEW, let window = notif.object as? NSWindow else { return }
            if window.isSettingsWindow {
                log.debug("Starting settings tab key monitor")
                tabKeyMonitor.start()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notif in
            guard !SWIFTUI_PREVIEW, let window = notif.object as? NSWindow else { return }
            if window.isSettingsWindow {
                log.debug("Stopping settings tab key monitor")
                tabKeyMonitor.stop()
            }
        }
    }

    private struct PreventSidebarCollapse: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            DisablingView()
        }
        func updateNSView(_ nsView: NSView, context: Context) {}

        // `navigationSplitViewColumnWidth(min:)` only limits live resizing: dragging past
        // the minimum still snaps the sidebar closed, and without a sidebar toggle there is
        // no way to bring it back. SwiftUI has no API for this, so forbid collapsing on the
        // underlying `NSSplitViewController` and expand a sidebar that is already collapsed
        // (e.g. persisted from a previous session). Lives on the detail column: a collapsed
        // sidebar's view is out of the hierarchy, so a sidebar-attached helper would never run.
        private final class DisablingView: NSView {
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard window != nil else { return }
                DispatchQueue.main.async { [weak self] in self?.disableSidebarCollapse() }
            }

            override func layout() {
                super.layout()
                disableSidebarCollapse()
            }

            private func disableSidebarCollapse() {
                var view = superview
                while let v = view, !(v is NSSplitView) {
                    view = v.superview
                }
                guard let splitView = view as? NSSplitView,
                      let controller = splitView.delegate as? NSSplitViewController else { return }
                for item in controller.splitViewItems {
                    item.canCollapse = false
                    if item.isCollapsed {
                        item.isCollapsed = false
                    }
                }
            }
        }

    }

    @ViewBuilder
    private var detailView: some View {
        switch svm.tab {
        case .general: GeneralSettingsView()
        case .clipboard: ClipboardSettingsView()
        case .files: FileHandlingSettingsView()
        case .video: VideoSettingsView()
        case .audio: AudioSettingsView()
        case .images: ImagesSettingsView()
        case .pdf: PDFSettingsView()
        case .results: ResultsSettingsView()
        case .keys: KeysSettingsView()
        case .pipelines: PipelinesSettingsView()
        case .mcp: MCPSettingsView()
        case .about:
            AboutSettingsView()
                .overlay(alignment: .bottomTrailing) {
                    LegalNotice().padding(Space.s)
                }
        }
    }

}

@MainActor var tabKeyMonitor = LocalEventMonitor(mask: .keyDown) { event in
    guard let combo = event.keyCombo else { return event }

    if combo.modifierFlags == [.command, .shift] {
        switch combo.key {
        case .leftBracket:
            settingsViewManager.tab = settingsViewManager.tab.previous
        case .rightBracket:
            settingsViewManager.tab = settingsViewManager.tab.next
        default:
            return event
        }
        return nil
    }

    if combo.modifierFlags == [.command], let num = combo.key.character.i, let tab = SettingsView.Tabs(rawValue: num - 1) {
        settingsViewManager.tab = tab
        return nil
    }
    return event
}

// MARK: - Skip-rule sliders

/// Human-readable file size for slider labels (KB / MB / GB).
func formatSkipFileSize(_ bytes: Double) -> String {
    if bytes >= 1_000_000_000 {
        String(format: "%.1f GB", bytes / 1_000_000_000)
    } else if bytes >= 1_000_000 {
        String(format: "%.0f MB", bytes / 1_000_000)
    } else {
        String(format: "%.0f KB", bytes / 1000)
    }
}

struct SkipSliderKnob: View {
    var body: some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
    }
}

/// Two-knob range slider operating on normalised fractions (0...1). The left knob is clamped
/// to never pass the right knob and vice versa. Callers map fractions to/from their domain.
struct DualKnobSlider: View {
    @Binding var low: Double
    @Binding var high: Double

    /// Name for the two stand-in accessibility sliders ("File size minimum", "File size maximum").
    var label = ""

    var onChanged: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let usable = max(1, w - thumb)
            let lowX = thumb / 2 + CGFloat(low) * usable
            let highX = thumb / 2 + CGFloat(high) * usable
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: track)
                Capsule().fill(Color.accentColor.opacity(0.7))
                    .frame(width: max(0, highX - lowX), height: track)
                    .position(x: (lowX + highX) / 2, y: thumb / 2)
                SkipSliderKnob().frame(width: thumb, height: thumb).position(x: lowX, y: thumb / 2)
                    .gesture(knobDrag(usable: usable, lower: true))
                    .accessibilitySlider("\(label) minimum", position: Binding(
                        get: { low },
                        set: { low = Swift.min(high, Swift.max(0, $0)); onChanged() }
                    ))
                SkipSliderKnob().frame(width: thumb, height: thumb).position(x: highX, y: thumb / 2)
                    .gesture(knobDrag(usable: usable, lower: false))
                    .accessibilitySlider("\(label) maximum", position: Binding(
                        get: { high },
                        set: { high = Swift.max(low, Swift.min(1, $0)); onChanged() }
                    ))
            }
            .frame(width: w, height: thumb)
            .coordinateSpace(name: space)
        }
        .frame(height: thumb)
    }

    private let thumb: CGFloat = 16
    private let track: CGFloat = 4
    private let space = "dualKnobSlider"

    private func knobDrag(usable: CGFloat, lower: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { v in
                let f = Double((v.location.x - thumb / 2) / usable)
                if lower {
                    low = Swift.min(high, Swift.max(0, f))
                } else {
                    high = Swift.max(low, Swift.min(1, f))
                }
            }
            .onEnded { _ in onChanged() }
    }
}

/// One-knob slider on normalised fractions (0...1); click or drag anywhere on the track.
struct SingleKnobSlider: View {
    @Binding var value: Double

    /// Name of the stand-in accessibility slider: the track is a drag gesture, invisible to it.
    var label = ""

    var onChanged: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let usable = max(1, w - thumb)
            let x = thumb / 2 + CGFloat(value) * usable
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: track)
                Capsule().fill(Color.accentColor.opacity(0.7))
                    .frame(width: max(0, x - thumb / 2), height: track)
                    .position(x: (thumb / 2 + x) / 2, y: thumb / 2)
                SkipSliderKnob().frame(width: thumb, height: thumb).position(x: x, y: thumb / 2)
            }
            .frame(width: w, height: thumb)
            .coordinateSpace(name: space)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                    .onChanged { v in
                        value = Swift.min(1, Swift.max(0, Double((v.location.x - thumb / 2) / usable)))
                    }
                    .onEnded { _ in onChanged() }
            )
        }
        .frame(height: thumb)
        .accessibilitySlider(label, position: Binding(
            get: { value },
            set: { value = Swift.min(1, Swift.max(0, $0)); onChanged() }
        ))
    }

    private let thumb: CGFloat = 16
    private let track: CGFloat = 4
    private let space = "singleKnobSlider"

}

/// File size skip range. min is stored in KB, max in MB; 0 disables that bound. Log-scaled.
struct FileSizeRangeRow: View {
    var label = "File size"

    @Binding var minKB: Int
    @Binding var maxMB: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(label).regular(TextSize.body)
                Spacer()
                Text("\(minKB == 0 ? "0" : formatSkipFileSize(Double(minKB) * 1000)) - \(maxMB == 0 ? "∞" : formatSkipFileSize(Double(maxMB) * 1_000_000))")
                    .mono(TextSize.subheadline).foregroundColor(.secondary)
            }
            DualKnobSlider(
                low: Binding(get: { minKB == 0 ? 0 : frac(Double(minKB) * 1000) }, set: setLow),
                high: Binding(get: { maxMB == 0 ? 1 : frac(Double(maxMB) * 1_000_000) }, set: setHigh),
                label: label
            )
            Text(caption).round(TextSize.caption, weight: .regular).foregroundColor(.secondary)
        }
    }

    private let lo = 1000.0 // 1 KB
    private let hi = 10_000_000_000.0 // 10 GB

    private var caption: String {
        let minS = formatSkipFileSize(Double(minKB) * 1000)
        let maxS = formatSkipFileSize(Double(maxMB) * 1_000_000)
        return switch (minKB > 0, maxMB > 0) {
        case (true, true): "Only optimises files between \(minS) and \(maxS)"
        case (true, false): "Only optimises files larger than \(minS)"
        case (false, true): "Only optimises files smaller than \(maxS)"
        case (false, false): "Optimises files of any size"
        }
    }

    private func frac(_ bytes: Double) -> Double {
        let b = Swift.max(lo, Swift.min(hi, bytes))
        return (log2(b) - log2(lo)) / (log2(hi) - log2(lo))
    }

    private func bytes(_ f: Double) -> Double {
        lo * pow(hi / lo, f)
    }
    private func setLow(_ f: Double) {
        minKB = f <= 0 ? 0 : Int((bytes(f) / 1000).rounded())
    }
    private func setHigh(_ f: Double) {
        maxMB = f >= 1 ? 0 : Swift.max(1, Int((bytes(f) / 1_000_000).rounded()))
    }
}

/// Resolution skip range (px on either side). 0 disables that bound. Linear scale to 8000px.
struct ResolutionRangeRow: View {
    var label = "Resolution"

    @Binding var minRes: Int
    @Binding var maxRes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(label).regular(TextSize.body)
                Spacer()
                Text("\(minRes == 0 ? "0" : "\(minRes)") - \(maxRes == 0 ? "∞" : "\(maxRes)") px")
                    .mono(TextSize.subheadline).foregroundColor(.secondary)
            }
            DualKnobSlider(
                low: Binding(get: { minRes == 0 ? 0 : frac(Double(minRes)) }, set: setLow),
                high: Binding(get: { maxRes == 0 ? 1 : frac(Double(maxRes)) }, set: setHigh),
                label: label
            )
            Text(caption).round(TextSize.caption, weight: .regular).foregroundColor(.secondary)
        }
    }

    private let lo = 16.0
    private let hi = 30000.0

    private var caption: String {
        switch (minRes > 0, maxRes > 0) {
        case (true, true): "Only optimises files with width and height between \(minRes) and \(maxRes)px"
        case (true, false): "Only optimises files with width and height over \(minRes)px"
        case (false, true): "Only optimises files with width and height under \(maxRes)px"
        case (false, false): "Optimises files of any resolution"
        }
    }

    private func frac(_ px: Double) -> Double {
        let p = Swift.max(lo, Swift.min(hi, px))
        return (log2(p) - log2(lo)) / (log2(hi) - log2(lo))
    }

    private func pixels(_ f: Double) -> Double {
        lo * pow(hi / lo, f)
    }
    /// Round to nicer steps: 10px under 1000, 50px above, where the slider gets coarse.
    private func snap(_ f: Double) -> Int {
        let px = pixels(f)
        let step = px < 1000 ? 10.0 : 50.0
        return Int((px / step).rounded()) * Int(step)
    }

    private func setLow(_ f: Double) {
        minRes = f <= 0 ? 0 : snap(f)
    }
    private func setHigh(_ f: Double) {
        maxRes = f >= 1 ? 0 : Swift.max(10, snap(f))
    }
}

/// One-knob stepped slider for integer counts.
struct CountSliderRow: View {
    var label = "File count"
    @Binding var count: Int

    var range: ClosedRange<Int> = 1 ... 100
    var caption: (Int) -> String = { _ in "" }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(label).regular(TextSize.body)
                Spacer()
                Text("\(count)").mono(TextSize.subheadline).foregroundColor(.secondary)
            }
            SingleKnobSlider(value: Binding(
                get: { Double(count - range.lowerBound) / Double(range.upperBound - range.lowerBound) },
                set: { count = range.lowerBound + Int(($0 * Double(range.upperBound - range.lowerBound)).rounded()) }
            ), label: label)
            if !caption(count).isEmpty {
                Text(caption(count)).round(TextSize.caption, weight: .regular).foregroundColor(.secondary)
            }
        }
    }
}

struct SkipSliderPreview: View {
    @State var minKB = 100
    @State var maxMB = 500
    @State var minRes = 100
    @State var maxRes = 4000
    @State var count = 4

    var body: some View {
        Form {
            Section(header: Text("Skip rules preview")) {
                FileSizeRangeRow(minKB: $minKB, maxMB: $maxMB)
                ResolutionRangeRow(minRes: $minRes, maxRes: $maxRes)
                CountSliderRow(count: $count, caption: { "Skips optimisation when more than \($0) \($0 == 1 ? "image is" : "images are") copied or moved at once" })
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 420)
    }
}

#Preview { SkipSliderPreview() }

struct FloatingSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        FloatingSettingsView()
            .formStyle(.grouped)
            .frame(width: WINDOW_MIN_SIZE.width, height: WINDOW_MIN_SIZE.height, alignment: .topLeading)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let _ = (settingsViewManager.windowOpen = true)
        SettingsView()
            .frame(minWidth: WINDOW_MIN_SIZE.width, maxWidth: .infinity, minHeight: WINDOW_MIN_SIZE.height, maxHeight: .infinity)
    }
}
