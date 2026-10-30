import Combine
import Foundation
import PencilKit
import UIKit

@MainActor
final class NotebookLibrary: ObservableObject {
    @Published private(set) var notebooks: [Notebook] = []
    @Published var errorMessage: String?

    private let root: URL
    private var pendingDrawings: [URL: PKDrawing] = [:]
    private var pendingSave: DispatchWorkItem?
    private var canWrite = false

    init() {
        root = URL.documentsDirectory.appending(path: "AlphaNoteBook", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let index = root.appending(path: "Library.json")
            if FileManager.default.fileExists(atPath: index.path) {
                notebooks = try JSONDecoder().decode([Notebook].self, from: Data(contentsOf: index))
                guard notebooks.allSatisfy({ !$0.pages.isEmpty && Set($0.pages).count == $0.pages.count }),
                      Set(notebooks.map(\.id)).count == notebooks.count else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
            canWrite = true
        } catch {
            errorMessage = "无法读取笔记本。为保护原有文件，本次不会覆盖资料。\n\(error.localizedDescription)"
        }
    }

    var isReadOnly: Bool { !canWrite }

    func notebook(_ id: UUID) -> Notebook? {
        notebooks.first { $0.id == id }
    }

    @discardableResult
    func createNotebook() -> UUID? {
        guard canWrite else { return nil }
        var number = notebooks.count + 1
        while notebooks.contains(where: { $0.title == "笔记本 \(number)" }) { number += 1 }
        let notebook = Notebook.create(title: "笔记本 \(number)")
        do {
            try FileManager.default.createDirectory(at: directory(notebook.id), withIntermediateDirectories: true)
            notebooks.insert(notebook, at: 0)
            if !saveIndex() {
                notebooks.removeAll { $0.id == notebook.id }
                return nil
            }
            return notebook.id
        } catch {
            report(error)
            return nil
        }
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.title = trimmed }
    }

    func delete(_ id: UUID) {
        guard canWrite, notebook(id) != nil else { return }
        flush()
        guard pendingDrawings.isEmpty else { return }
        let previous = notebooks
        notebooks.removeAll { $0.id == id }
        guard saveIndex() else {
            notebooks = previous
            return
        }
        do {
            if FileManager.default.fileExists(atPath: directory(id).path) {
                try FileManager.default.removeItem(at: directory(id))
            }
        } catch { report(error) }
    }

    func update(_ id: UUID, change: (inout Notebook) -> Void) {
        guard canWrite, let index = notebooks.firstIndex(where: { $0.id == id }) else { return }
        let previous = notebooks[index]
        change(&notebooks[index])
        notebooks[index].updatedAt = .now
        if !saveIndex() { notebooks[index] = previous }
    }

    func setPage(_ pageID: UUID, in bookID: UUID) {
        guard let book = notebook(bookID), book.currentPageID != pageID,
              book.pages.contains(pageID) else { return }
        update(bookID) { $0.currentPageID = pageID }
    }

    @discardableResult
    func appendPage(_ pageID: UUID, in bookID: UUID) -> Bool {
        guard canWrite, let index = notebooks.firstIndex(where: { $0.id == bookID }) else { return false }
        guard !notebooks[index].pages.contains(pageID) else { return true }
        let previous = notebooks[index]
        notebooks[index].pages.append(pageID)
        notebooks[index].currentPageID = pageID
        notebooks[index].updatedAt = .now
        guard saveIndex() else {
            notebooks[index] = previous
            return false
        }
        return true
    }

    func setPageSize(_ size: CGSize, in bookID: UUID) {
        guard let book = notebook(bookID), book.pageWidth == 0,
              size.width > 0, size.height > 0 else { return }
        update(bookID) {
            $0.pageWidth = Double(size.width)
            $0.pageHeight = Double(size.height)
        }
    }

    func drawing(bookID: UUID, pageID: UUID) throws -> PKDrawing {
        let url = drawingURL(bookID: bookID, pageID: pageID)
        if let pending = pendingDrawings[url] { return pending }
        guard FileManager.default.fileExists(atPath: url.path) else { return PKDrawing() }
        return try PKDrawing(data: Data(contentsOf: url))
    }

    func queueDrawing(_ drawing: PKDrawing, bookID: UUID, pageID: UUID) {
        guard canWrite, notebook(bookID)?.pages.contains(pageID) == true else { return }
        pendingDrawings[drawingURL(bookID: bookID, pageID: pageID)] = drawing
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard canWrite else { return }
        for (url, drawing) in Array(pendingDrawings) {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try drawing.dataRepresentation().write(to: url, options: .atomic)
                pendingDrawings.removeValue(forKey: url)
            } catch { report(error) }
        }
    }

    func exportPDF(_ bookID: UUID) throws -> URL {
        flush()
        guard let book = notebook(bookID) else { throw CocoaError(.fileNoSuchFile) }
        let bounds = CGRect(origin: .zero, size: book.pageSize)
        let exportDirectory = FileManager.default.temporaryDirectory
            .appending(path: "Exports", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let safeName = book.title.components(separatedBy: CharacterSet(charactersIn: "/\\:")
            .union(.controlCharacters)).joined(separator: "-")
        let url = exportDirectory.appending(path: "\(safeName.isEmpty ? "AlphaNoteBook" : safeName).pdf")
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: book.title,
            kCGPDFContextCreator as String: "AlphaNoteBook"
        ]
        var drawingError: Error?
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        try renderer.writePDF(to: url) { context in
            for pageID in book.pages {
                autoreleasepool {
                    context.beginPage()
                    book.paperColor.uiColor.setFill()
                    context.fill(bounds)
                    do {
                        let drawing = try self.drawing(bookID: bookID, pageID: pageID)
                        drawing.image(from: bounds, scale: 2).draw(in: bounds)
                    } catch { drawingError = error }
                }
            }
        }
        if let drawingError { throw drawingError }
        return url
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private func directory(_ bookID: UUID) -> URL {
        root.appending(path: bookID.uuidString, directoryHint: .isDirectory)
    }

    private func drawingURL(bookID: UUID, pageID: UUID) -> URL {
        directory(bookID).appending(path: "\(pageID.uuidString).drawing")
    }

    @discardableResult
    private func saveIndex() -> Bool {
        guard canWrite else { return false }
        do {
            let data = try JSONEncoder().encode(notebooks)
            try data.write(to: root.appending(path: "Library.json"), options: .atomic)
            return true
        } catch {
            report(error)
            return false
        }
    }
}
