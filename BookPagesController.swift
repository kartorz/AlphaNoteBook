import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct BookPagesView: UIViewControllerRepresentable {
    let bookID: UUID
    let library: NotebookLibrary
    let actions: EditorActions

    func makeUIViewController(context: Context) -> BookPagesController {
        BookPagesController(bookID: bookID, library: library, actions: actions)
    }

    func updateUIViewController(_ controller: BookPagesController, context: Context) {
        controller.applySettings()
    }

    static func dismantleUIViewController(_ controller: BookPagesController, coordinator: ()) {
        controller.saveCurrentPage()
    }
}

@MainActor
final class BookPagesController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let bookID: UUID
    private let library: NotebookLibrary
    private let actions: EditorActions
    private let pageController: UIPageViewController
    private var cornerGate: CornerGestureGate?
    private var turning = false

    private var currentPage: HandwritingPageController? {
        pageController.viewControllers?.first as? HandwritingPageController
    }

    init(bookID: UUID, library: NotebookLibrary, actions: EditorActions) {
        self.bookID = bookID
        self.library = library
        self.actions = actions
        pageController = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)]
        )
        super.init(nibName: nil, bundle: nil)
        actions.controller = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        pageController.dataSource = self
        pageController.delegate = self
        pageController.isDoubleSided = false
        addChild(pageController)
        view.addSubview(pageController.view)
        pageController.didMove(toParent: self)
        if let book = library.notebook(bookID), let first = book.pages.first {
            let initial = book.pages.contains(book.currentPageID) ? book.currentPageID : first
            pageController.setViewControllers([makePage(initial)], direction: .forward, animated: false)
        }
        let gate = CornerGestureGate()
        gate.cancelsTouchesInView = false
        gate.delaysTouchesBegan = false
        gate.isWriting = { [weak self] in self?.currentPage?.isUsingTool == true }
        pageController.view.addGestureRecognizer(gate)
        cornerGate = gate
        for gesture in pageController.gestureRecognizers {
            gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            gesture.requiresExclusiveTouchType = true
            gesture.require(toFail: gate)
        }
        applySettings()
        publishState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pageController.view.frame = view.bounds
    }

    func applySettings() {
        guard isViewLoaded, let book = library.notebook(bookID) else { return }
        view.backgroundColor = book.paperColor.uiColor
        pageController.view.backgroundColor = book.paperColor.uiColor
        for page in pageController.viewControllers ?? [] {
            (page as? HandwritingPageController)?.applySettings()
        }
    }

    func saveCurrentPage() {
        currentPage?.saveDrawing()
        library.flush()
    }

    func undoStroke() {
        guard !turning, currentPage?.isUsingTool != true else { return }
        currentPage?.canvas.undoManager?.undo()
        currentPage?.saveDrawing()
        publishState()
    }

    func redoStroke() {
        guard !turning, currentPage?.isUsingTool != true else { return }
        currentPage?.canvas.undoManager?.redo()
        currentPage?.saveDrawing()
        publishState()
    }

    func turnPage(forward: Bool) {
        guard !turning, let current = currentPage, !current.isUsingTool else { return }
        let destination = forward
            ? pageViewController(pageController, viewControllerAfter: current)
            : pageViewController(pageController, viewControllerBefore: current)
        guard let destination = destination as? HandwritingPageController else { return }
        saveCurrentPage()
        setTurning(true)
        pageController.setViewControllers([destination], direction: forward ? .forward : .reverse,
                                          animated: true) { [weak self] completed in
            guard let self else { return }
            if completed { self.commitVisiblePage() }
            self.setTurning(false)
            self.publishState()
        }
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? HandwritingPageController,
              let book = library.notebook(bookID) else { return nil }
        if page.isDraft { return book.pages.last.map { makePage($0) } }
        guard let index = book.pages.firstIndex(of: page.pageID), index > 0 else { return nil }
        return makePage(book.pages[index - 1])
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? HandwritingPageController, !page.isDraft,
              let book = library.notebook(bookID),
              let index = book.pages.firstIndex(of: page.pageID) else { return nil }
        if index + 1 < book.pages.count { return makePage(book.pages[index + 1]) }
        return makePage(UUID(), isDraft: true)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            willTransitionTo pendingViewControllers: [UIViewController]) {
        saveCurrentPage()
        for page in pendingViewControllers {
            (page as? HandwritingPageController)?.applySettings()
        }
        setTurning(true)
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed { commitVisiblePage() }
        setTurning(false)
        publishState()
    }

    private func makePage(_ id: UUID, isDraft: Bool = false) -> HandwritingPageController {
        let page = HandwritingPageController(pageID: id, bookID: bookID, library: library, isDraft: isDraft)
        page.onStateChange = { [weak self] in self?.publishState() }
        page.onToolUseChange = { [weak self] writing in
            guard let self else { return }
            for gesture in self.pageController.gestureRecognizers { gesture.isEnabled = !writing }
        }
        return page
    }

    private func commitVisiblePage() {
        guard let page = currentPage else { return }
        if page.isDraft {
            guard library.appendPage(page.pageID, in: bookID) else {
                if let book = library.notebook(bookID), let last = book.pages.last {
                    pageController.setViewControllers([makePage(last)], direction: .reverse, animated: false)
                }
                return
            }
            page.isDraft = false
        }
        library.setPage(page.pageID, in: bookID)
        page.applySettings()
    }

    private func setTurning(_ value: Bool) {
        turning = value
        publishState()
    }

    private func publishState() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let book = self.library.notebook(self.bookID) else { return }
            let page = self.currentPage
            let number = book.pages.firstIndex(of: page?.pageID ?? book.currentPageID).map { $0 + 1 } ?? book.pages.count
            let canUndo = page?.canvas.undoManager?.canUndo == true
            let canRedo = page?.canvas.undoManager?.canRedo == true
            if self.actions.pageNumber != number { self.actions.pageNumber = number }
            if self.actions.totalPages != book.pages.count { self.actions.totalPages = book.pages.count }
            if self.actions.canUndo != canUndo { self.actions.canUndo = canUndo }
            if self.actions.canRedo != canRedo { self.actions.canRedo = canRedo }
            if self.actions.isTurning != self.turning { self.actions.isTurning = self.turning }
        }
    }
}

private final class CornerGestureGate: UIGestureRecognizer {
    var isWriting: (() -> Bool)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else {
            state = .failed
            return
        }
        let location = touch.location(in: view)
        let inCorner = location.y >= view.bounds.height - 130 &&
            (location.x <= 110 || location.x >= view.bounds.width - 110)
        if state == .possible {
            state = touch.type == .direct && inCorner && isWriting?() != true && event.allTouches?.count == 1
                ? .failed : .began
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .began || state == .changed { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .began || state == .changed { state = .ended }
        else if state == .possible { state = .failed }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .began || state == .changed { state = .cancelled }
        else if state == .possible { state = .failed }
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
