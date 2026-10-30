import Combine
import SwiftUI

@MainActor
final class EditorActions: ObservableObject {
    @Published var pageNumber = 1
    @Published var totalPages = 1
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var isTurning = false
    weak var controller: BookPagesController?

    func undo() { controller?.undoStroke() }
    func redo() { controller?.redoStroke() }
    func previous() { controller?.turnPage(forward: false) }
    func next() { controller?.turnPage(forward: true) }
}

struct NotebookEditor: View {
    let bookID: UUID
    @EnvironmentObject private var library: NotebookLibrary
    @Environment(\.dismiss) private var dismiss
    @StateObject private var actions = EditorActions()
    @State private var menuVisible = false
    @State private var sharedPDF: SharedPDF?

    private var book: Notebook? { library.notebook(bookID) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let book {
                Color(book.paperColor.uiColor).ignoresSafeArea()
                BookPagesView(bookID: bookID, library: library, actions: actions)
                    .ignoresSafeArea()
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            menuVisible.toggle()
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(book.paperColor.foreground.opacity(0.65))
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("笔记本菜单")
                        .popover(isPresented: $menuVisible, arrowEdge: .top) {
                            editorMenu(book)
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        cornerButton("chevron.left", label: "上一页", book: book,
                                     disabled: actions.pageNumber <= 1 || actions.isTurning) {
                            actions.previous()
                        }
                        Spacer()
                        Text("\(actions.pageNumber) / \(actions.totalPages)")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(book.paperColor.foreground.opacity(0.3))
                            .padding(.bottom, 8)
                            .allowsHitTesting(false)
                        Spacer()
                        cornerButton("chevron.right", label: "下一页", book: book,
                                     disabled: actions.isTurning) {
                            actions.next()
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .interactiveDismissDisabled()
        .onDisappear { library.flush() }
        .sheet(item: $sharedPDF) { ShareSheet(url: $0.url) }
        .alert("无法完成操作", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    private func cornerButton(_ symbol: String, label: String, book: Notebook,
                              disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(book.paperColor.foreground.opacity(disabled ? 0.08 : 0.3))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private func editorMenu(_ book: Notebook) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    menuVisible = false
                    library.flush()
                    dismiss()
                } label: {
                    Image(systemName: "books.vertical")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("返回书架")
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("钢笔粗细")
                Picker("钢笔粗细", selection: Binding(
                    get: { book.penWidth },
                    set: { width in library.update(bookID) { $0.penWidth = width } }
                )) {
                    ForEach(PenWidth.allCases) { width in
                        Text(width.name).tag(width)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("笔迹颜色")
                HStack(spacing: 14) {
                    ForEach(InkColor.allCases) { color in
                        colorButton(color.uiColor, name: color.name, selected: book.inkColor == color) {
                            library.update(bookID) { $0.inkColor = color }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("整本纸张颜色")
                HStack(spacing: 14) {
                    ForEach(PaperColor.allCases) { color in
                        colorButton(color.uiColor, name: color.name, selected: book.paperColor == color) {
                            library.update(bookID) { $0.paperColor = color }
                        }
                    }
                }
            }

            Divider()
            HStack {
                Button { actions.undo() } label: {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                }
                .disabled(!actions.canUndo || actions.isTurning)
                Spacer()
                Button { actions.redo() } label: {
                    Label("重做", systemImage: "arrow.uturn.forward")
                }
                .disabled(!actions.canRedo || actions.isTurning)
            }
            Divider()
            Button {
                menuVisible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    do { sharedPDF = SharedPDF(url: try library.exportPDF(bookID)) }
                    catch { library.report(error) }
                }
            } label: {
                Label("整本导出 PDF", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Apple Pencil 写字 · 从下方页角翻页")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(24)
        .frame(width: 320)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.caption).foregroundStyle(.secondary)
    }

    private func colorButton(_ color: UIColor, name: String, selected: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color(color))
                .frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 1))
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
