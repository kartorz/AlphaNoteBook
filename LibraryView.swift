import SwiftUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var library: NotebookLibrary
    @State private var openedBook: OpenedBook?
    @State private var renamedBook: Notebook?
    @State private var newTitle = ""
    @State private var deletedBook: Notebook?
    @State private var sharedPDF: SharedPDF?

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.notebooks.isEmpty {
                    ContentUnavailableView {
                        Label("你的第一本笔记", systemImage: "book.closed")
                    } description: {
                        Text("新建一本，拿起 Apple Pencil 开始写。")
                    } actions: {
                        Button("新建笔记本", action: createNotebook)
                            .buttonStyle(.borderedProminent)
                            .tint(.primary)
                    }
                    .padding(.top, 140)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 230))], spacing: 32) {
                        ForEach(library.notebooks) { book in
                            Button {
                                openedBook = OpenedBook(id: book.id)
                            } label: {
                                NotebookCover(book: book)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("重命名", systemImage: "pencil") {
                                    newTitle = book.title
                                    renamedBook = book
                                }
                                Button("导出 PDF", systemImage: "square.and.arrow.up") { export(book.id) }
                                Button("删除", systemImage: "trash", role: .destructive) { deletedBook = book }
                            }
                        }
                    }
                    .padding(32)
                }
            }
            .background(Color(red: 0.96, green: 0.95, blue: 0.93))
            .navigationTitle("AlphaNoteBook")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("\(library.notebooks.count) 本笔记本")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新建笔记本", systemImage: "plus", action: createNotebook)
                }
            }
        }
        .fullScreenCover(item: $openedBook, onDismiss: { library.flush() }) { selected in
            NotebookEditor(bookID: selected.id)
                .environmentObject(library)
        }
        .alert("无法完成操作", isPresented: errorPresented) {
            Button("好", role: .cancel) { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "")
        }
        .alert("重命名笔记本", isPresented: Binding(
            get: { renamedBook != nil }, set: { if !$0 { renamedBook = nil } }
        )) {
            TextField("笔记本名称", text: $newTitle)
            Button("取消", role: .cancel) { renamedBook = nil }
            Button("保存") {
                if let book = renamedBook { library.rename(book.id, to: newTitle) }
                renamedBook = nil
            }
        }
        .confirmationDialog("删除这本笔记本？", isPresented: Binding(
            get: { deletedBook != nil }, set: { if !$0 { deletedBook = nil } }
        ), titleVisibility: .visible) {
            Button("删除笔记本", role: .destructive) {
                if let book = deletedBook { library.delete(book.id) }
                deletedBook = nil
            }
        } message: {
            Text("所有页面都将删除，此操作无法撤销。")
        }
        .sheet(item: $sharedPDF) { ShareSheet(url: $0.url) }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { library.errorMessage != nil && openedBook == nil },
                set: { if !$0 { library.errorMessage = nil } })
    }

    private func createNotebook() {
        if let id = library.createNotebook() { openedBook = OpenedBook(id: id) }
    }

    private func export(_ id: UUID) {
        do { sharedPDF = SharedPDF(url: try library.exportPDF(id)) }
        catch { library.report(error) }
    }
}

private struct NotebookCover: View {
    let book: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(book.paperColor.uiColor))
                Rectangle()
                    .fill(.black.opacity(0.12))
                    .frame(width: 10)
                    .padding(.leading, 9)
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "pencil.tip")
                        .font(.title2.weight(.light))
                    Text(book.title)
                        .font(.title3.weight(.medium))
                        .lineLimit(4)
                    Spacer()
                    Text("AlphaNoteBook")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .tracking(1)
                        .opacity(0.5)
                }
                .foregroundStyle(book.paperColor.foreground.opacity(0.8))
                .padding(.leading, 30)
                .padding(.trailing, 16)
                .padding(.vertical, 24)
            }
            .aspectRatio(0.72, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.black.opacity(0.07)))
            .shadow(color: .black.opacity(0.07), radius: 8, x: 2, y: 5)
            Text("\(book.pages.count) 页")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title)，\(book.pages.count) 页")
    }
}

private struct OpenedBook: Identifiable {
    let id: UUID
}

struct SharedPDF: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

}
