import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What the window is showing and doing.
@MainActor
final class Composer: ObservableObject {

    @Published var text = "Laugh, and the world laughs with you; weep, and you weep alone."
    @Published var styleID = 9
    /// tools/make_previews.py draws the picker's sample lines at this same
    /// neatness, so a style advertises what it actually writes
    @Published var neatness = 1.8
    @Published var penWidth = 2.0
    @Published var ink = Color.black
    @Published private(set) var page: Drawing.Page?
    @Published private(set) var samplePage: Drawing.Page?
    @Published private(set) var progress: Double?
    @Published private(set) var notice = ""
    @Published private(set) var status = ""
    @Published var failure: Failure?

    struct Failure {
        var title: String
        var message: String
    }

    private var generator: Generator?
    private var job: Task<Void, Never>?

    var isWriting: Bool { job != nil }
    var styles: [Styles.Style] { generator?.styles.all ?? [] }
    var inkColour: NSColor { NSColor(ink) }

    func load() {
        do {
            generator = try Generator()
            let ids = styles.map(\.id)
            if let first = ids.first, !ids.contains(styleID) { styleID = first }
            showSample()
        } catch {
            // the usual cause is the app being moved while it was open: the
            // running copy keeps pointing at files Finder has taken away
            failure = Failure(title: "Couldn't Load the Model", message: """
                If you just moved the app while it was open, quit it and open \
                it again from its new place. Otherwise this copy is incomplete \
                - download it again.
                """)
        }
    }

    /// The same sentence, written in the chosen style.
    func showSample() {
        guard let style = generator?.styles[styleID] else { return }
        samplePage = Drawing.page(of: [style.preview], margin: 6)
    }

    func write() {
        if let job {
            job.cancel()
            self.job = nil
            status = "Stopped."
            progress = nil
            return
        }
        guard let generator else { return }

        let (clean, dropped) = Alphabet.sanitize(text)
        let lines = Alphabet.wrap(clean)
        guard lines.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            status = "Type some text first."
            return
        }
        notice = dropped.isEmpty ? ""
            : "Skipped characters the model was never taught: "
                + dropped.map(String.init).joined(separator: " ")

        let request = Generator.Request(lines: lines, style: styleID, bias: Float(neatness),
                                        seed: UInt64.random(in: 0..<UInt64.max))
        progress = 0
        status = "Writing…"

        job = Task { [weak self] in
            let written = await Task.detached(priority: .userInitiated) { () -> [[SIMD3<Float>]] in
                generator.write(request) { fraction in
                    if Task.isCancelled { return false }
                    Task { @MainActor [weak self] in self?.progress = fraction }
                    return true
                }
            }.value

            guard let self, !Task.isCancelled else { return }
            let page = Drawing.page(of: written)
            self.page = page.isEmpty ? nil : page
            self.status = page.isEmpty ? "Nothing came out - try again."
                : "\(page.strokes.count.formatted()) strokes, "
                    + "\(written.reduce(0) { $0 + $1.count }.formatted()) points"
            self.progress = nil
            self.job = nil
        }
    }

    // MARK: - saving

    func exportFile(_ type: UTType) -> ExportFile? {
        page.map { ExportFile(page: $0, type: type, penWidth: penWidth, colour: inkColour) }
    }

    func exported(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): status = "Saved \(url.lastPathComponent)"
        case .failure(let error as CocoaError) where error.code == .userCancelled: break
        case .failure(let error):
            failure = Failure(title: "Couldn't Save the Image", message: error.localizedDescription)
        }
    }
}

struct ExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.png, .svg]
    let page: Drawing.Page
    let type: UTType
    let penWidth: CGFloat
    let colour: NSColor

    init(page: Drawing.Page, type: UTType, penWidth: CGFloat, colour: NSColor) {
        self.page = page
        self.type = type
        self.penWidth = penWidth
        self.colour = colour
    }

    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if type == .svg {
            return FileWrapper(regularFileWithContents:
                Data(Export.svg(page, penWidth: penWidth, colour: colour).utf8))
        }
        guard let png = Export.png(page, penWidth: penWidth, colour: colour) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: png)
    }
}
