import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var composer = Composer()
    @SceneStorage("showsInspector") private var showsInspector = true
    /// The format being saved while the save panel is open.
    @State private var exportType: UTType?

    var body: some View {
        withInspector(
            VStack(spacing: 12) {
                sample

                // what you type and what it becomes, side by side like two pages
                HStack(spacing: 14) {
                    editor
                    preview
                }
                .frame(maxHeight: .infinity)
            }
            .padding(18)
            .frame(minWidth: 620, minHeight: 520)
        )
        .navigationTitle(title)
        .navigationSubtitle(composer.status)
        .toolbar { toolbar }
        .focusedSceneValue(\.windowActions, WindowActions(
            write: composer.write, isWriting: composer.isWriting,
            export: composer.page == nil ? nil : { exportType = $0 },
            toggleInspector: { showsInspector.toggle() }, showsInspector: showsInspector))
        .fileExporter(isPresented: Binding(get: { exportType != nil },
                                           set: { if !$0 { exportType = nil } }),
                      document: exportType.flatMap(composer.exportFile),
                      contentType: exportType ?? .png, defaultFilename: "handwriting",
                      onCompletion: composer.exported)
        .transparentBackgroundMessage()
        .onAppear { composer.load() }
        .alert(composer.failure?.title ?? "", isPresented: Binding(
            get: { composer.failure != nil }, set: { if !$0 { composer.failure = nil } })) {
            Button("OK") { }
        } message: {
            Text(composer.failure?.message ?? "")
        }
    }

    /// The first words of the text, the way Notes titles a note.
    private var title: String {
        let first = composer.text.split(separator: "\n").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if first.isEmpty { return "Untitled" }
        return first.count > 24 ? first.prefix(24).trimmingCharacters(in: .whitespaces) + "…" : first
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let progress = composer.progress {
            ToolbarItem {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }
            .withoutSharedBackground()
        }
        ToolbarItem {
            Menu {
                Button("PNG Image…") { exportType = .png }
                Button("SVG Image…") { exportType = .svg }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Save the page as an image")
            .disabled(composer.page == nil)
        }
        ToolbarGap()
        ToolbarItem {
            Button(composer.isWriting ? "Stop" : "Write") { composer.write() }
                .prominentButton()
                .help(composer.isWriting ? "Stop writing" : "Write the text in the chosen hand")
        }
        ToolbarGap()
        ToolbarItem {
            Button { showsInspector.toggle() } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help(showsInspector ? "Hide the inspector" : "Show the inspector")
        }
    }

    /// The pen and the hand, beside the pages: a trailing inspector, or a
    /// fixed pane where macOS 13 has no inspector.
    @ViewBuilder private func withInspector(_ content: some View) -> some View {
        if #available(macOS 14, *) {
            content.inspector(isPresented: $showsInspector) {
                options.inspectorColumnWidth(min: 240, ideal: 270, max: 360)
            }
        } else {
            HStack(spacing: 0) {
                content
                if showsInspector {
                    Divider()
                    options.frame(width: 270)
                }
            }
        }
    }

    private var options: some View {
        Form {
            Section {
                Picker("Style", selection: $composer.styleID) {
                    ForEach(composer.styles, id: \.id) { Text($0.name).tag($0.id) }
                }
                .onChange(of: composer.styleID) { _ in composer.showSample() }
                LabeledContent("Neatness") {
                    ValueSlider(title: "Neatness", value: $composer.neatness, range: 0.3...2,
                                digits: 2)
                }
            } footer: {
                Text("Neatness steadies the hand: low wanders and scrawls, high writes carefully.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Pen") {
                LabeledContent("Width") {
                    ValueSlider(title: "Width", value: $composer.penWidth, range: 0.7...6,
                                digits: 1)
                }
                ColorPicker("Ink", selection: $composer.ink, supportsOpacity: false)
            }
        }
        .formStyle(.grouped)
    }

    /// The same sentence, written in the chosen style.
    private var sample: some View {
        PageView(page: composer.samplePage, ink: .secondary, penWidth: 2.4, maximumZoom: 1,
                 padding: 4)
            .frame(height: 66)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.35)))
            .overlay(alignment: .leading) {
                Text("style")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
            }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $composer.text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))

            if !composer.notice.isEmpty {
                Label(composer.notice, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A sheet of paper: the writing starts at the top left, as a letter would.
    private var preview: some View {
        PageView(page: composer.page, ink: composer.ink, penWidth: composer.penWidth,
                 maximumZoom: 2, padding: 14, anchor: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            .overlay {
                if composer.page == nil && !composer.isWriting { emptyPage }
            }
            // paper stays white in dark mode, so what is on it is drawn for light
            .environment(\.colorScheme, .light)
    }

    @ViewBuilder private var emptyPage: some View {
        if #available(macOS 14, *) {
            ContentUnavailableView("No Handwriting Yet", systemImage: "signature",
                                   description: Text("Press Write to see the text in the chosen hand."))
        } else {
            Text("Your handwriting appears here")
                .font(.callout)
                .foregroundStyle(Color(white: 0.68))
        }
    }
}

/// A slider that shows what it is set to.
private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let digits: Int

    var body: some View {
        HStack {
            Slider(value: $value, in: range) { Text(title) }
                .labelsHidden()
            Text(value.formatted(.number.precision(.fractionLength(digits))))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

/// Draws a page, scaled to fit and never blown up past `maximumZoom`.
struct PageView: View {
    let page: Drawing.Page?
    let ink: Color
    let penWidth: Double
    let maximumZoom: Double
    var padding: CGFloat = 8
    /// Where the page sits when it is smaller than the view.
    var anchor: UnitPoint = .center

    var body: some View {
        Canvas { context, size in
            guard let page, !page.isEmpty else { return }
            let zoom = min((size.width - 2 * padding) / page.size.width,
                           (size.height - 2 * padding) / page.size.height,
                           maximumZoom)
            let spareX = size.width - 2 * padding - page.size.width * zoom
            let spareY = size.height - 2 * padding - page.size.height * zoom
            context.translateBy(x: padding + spareX * anchor.x, y: padding + spareY * anchor.y)
            context.scaleBy(x: zoom, y: zoom)
            let stroke = StrokeStyle(lineWidth: penWidth, lineCap: .round, lineJoin: .round)
            for line in page.strokes {
                context.stroke(Path(Drawing.path(for: line)), with: .color(ink), style: stroke)
            }
        }
    }
}

// MARK: - menu bar

/// What the menu bar can do to the front window; a nil action is a disabled item.
struct WindowActions {
    var write: () -> Void
    var isWriting: Bool
    var export: ((UTType) -> Void)?
    var toggleInspector: () -> Void
    var showsInspector: Bool
}

extension FocusedValues {
    @Entry var windowActions: WindowActions?
}

struct WindowCommands: Commands {
    @FocusedValue(\.windowActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(actions?.isWriting == true ? "Stop" : "Write") { actions?.write() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(actions == nil)
        }
        CommandGroup(replacing: .importExport) {
            Group {
                Button("Export as PNG…") { actions?.export?(.png) }
                    .keyboardShortcut("e")
                Button("Export as SVG…") { actions?.export?(.svg) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            .disabled(actions?.export == nil)
        }
        CommandGroup(after: .sidebar) {
            Button(actions?.showsInspector == false ? "Show Inspector" : "Hide Inspector") {
                actions?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .control])
            .disabled(actions == nil)
        }
    }
}

// MARK: - Liquid Glass, with plain fallbacks before macOS 26

extension View {
    /// Tinted Liquid Glass for the one primary toolbar action; a bordered prominent button before macOS 26.
    @ViewBuilder func prominentButton() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glassProminent) } else { buttonStyle(.borderedProminent) }
    }

    /// Says in the save panel that images come without a background; macOS 13 has no message.
    @ViewBuilder func transparentBackgroundMessage() -> some View {
        if #available(macOS 14, *) {
            fileDialogMessage("Images are saved with a transparent background.")
        } else { self }
    }
}

extension ToolbarContent {
    /// Items without the shared glass capsule (e.g. a spinner); older systems have no capsule anyway.
    @ToolbarContentBuilder func withoutSharedBackground() -> some ToolbarContent {
        if #available(macOS 26, *) { sharedBackgroundVisibility(.hidden) } else { self }
    }
}

/// A gap between toolbar groups on macOS 26; older toolbars have no glass groups to separate.
struct ToolbarGap: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26, *) { ToolbarSpacer(.fixed) }
    }
}
