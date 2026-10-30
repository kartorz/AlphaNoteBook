import SwiftUI

@main
struct AlphaNoteBookApp: App {
    @StateObject private var library = NotebookLibrary()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { library.flush() }
        }
    }
}
