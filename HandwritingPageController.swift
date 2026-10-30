import PencilKit
import UIKit

final class PageCanvasView: PKCanvasView {
    private let pageUndoManager = UndoManager()
    override var undoManager: UndoManager? { pageUndoManager }
}

@MainActor
final class HandwritingPageController: UIViewController, PKCanvasViewDelegate {
    let pageID: UUID
    let bookID: UUID
    let canvas = PageCanvasView()
    var isDraft: Bool
    var onStateChange: (() -> Void)?
    var onToolUseChange: ((Bool) -> Void)?
    private(set) var isUsingTool = false
    private let library: NotebookLibrary
    private var isLoading = true
    private var isReadable = true
    private var hasScheduledSize = false
    private var undoObservers: [NSObjectProtocol] = []

    init(pageID: UUID, bookID: UUID, library: NotebookLibrary, isDraft: Bool = false) {
        self.pageID = pageID
        self.bookID = bookID
        self.library = library
        self.isDraft = isDraft
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        canvas.delegate = self
        canvas.drawingPolicy = .pencilOnly
        canvas.drawingGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        canvas.isScrollEnabled = false
        canvas.bounces = false
        canvas.bouncesZoom = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.pinchGestureRecognizer?.isEnabled = false
        canvas.panGestureRecognizer.isEnabled = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.showsHorizontalScrollIndicator = false
        canvas.showsVerticalScrollIndicator = false
        canvas.isUserInteractionEnabled = !library.isReadOnly
        canvas.isOpaque = true
        canvas.clipsToBounds = true
        view.addSubview(canvas)
        do {
            if isDraft {
                canvas.drawing = PKDrawing()
            } else {
                canvas.drawing = try library.drawing(bookID: bookID, pageID: pageID)
            }
        } catch {
            isReadable = false
            canvas.isUserInteractionEnabled = false
            let warning = UILabel()
            warning.text = "此页暂时无法读取\n为保护笔迹，已停止编辑"
            warning.numberOfLines = 0
            warning.textAlignment = .center
            warning.textColor = .secondaryLabel
            warning.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(warning)
            NSLayoutConstraint.activate([
                warning.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                warning.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            DispatchQueue.main.async { [weak self] in self?.library.report(error) }
        }
        canvas.undoManager?.removeAllActions()
        isLoading = false
        applySettings()
        for name in [Notification.Name.NSUndoManagerDidUndoChange,
                     Notification.Name.NSUndoManagerDidRedoChange,
                     Notification.Name.NSUndoManagerDidCloseUndoGroup] {
            let observer = NotificationCenter.default.addObserver(
                forName: name, object: canvas.undoManager, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.onStateChange?() }
            }
            undoObservers.append(observer)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let book = library.notebook(bookID), view.bounds.width > 0,
              view.bounds.height > 0 else { return }
        let pageSize = book.pageWidth > 0 ? book.pageSize : view.bounds.size
        let scale = min(view.bounds.width / pageSize.width, view.bounds.height / pageSize.height)
        canvas.transform = .identity
        canvas.bounds = CGRect(origin: .zero, size: pageSize)
        canvas.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        canvas.contentSize = pageSize
        canvas.contentOffset = .zero
        canvas.transform = CGAffineTransform(scaleX: scale, y: scale)
        if book.pageWidth == 0, !hasScheduledSize {
            hasScheduledSize = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.library.setPageSize(pageSize, in: self.bookID)
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveDrawing()
        library.flush()
    }

    func applySettings() {
        guard isViewLoaded, let book = library.notebook(bookID) else { return }
        view.backgroundColor = book.paperColor.uiColor
        canvas.backgroundColor = book.paperColor.uiColor
        let selectedColor = book.inkColor.uiColor
        let selectedWidth = book.penWidth.points
        if let current = canvas.tool as? PKInkingTool,
           current.inkType == .pen, current.width == selectedWidth, current.color.isEqual(selectedColor) {
            return
        }
        canvas.tool = PKInkingTool(.pen, color: selectedColor, width: selectedWidth)
        view.setNeedsLayout()
    }

    func saveDrawing() {
        guard isViewLoaded, !isLoading, isReadable, !isDraft else { return }
        library.queueDrawing(canvas.drawing, bookID: bookID, pageID: pageID)
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isLoading else { return }
        saveDrawing()
        onStateChange?()
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        isUsingTool = true
        onToolUseChange?(true)
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        isUsingTool = false
        saveDrawing()
        library.flush()
        onToolUseChange?(false)
        onStateChange?()
    }

    deinit {
        for observer in undoObservers { NotificationCenter.default.removeObserver(observer) }
    }
}
