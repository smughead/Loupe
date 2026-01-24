import SwiftUI
import LoupeFeature

@main
struct LoupeApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView(coordinator: coordinator)
        }
        .commands {
            // Remove the default New Window command since we only want one window
            CommandGroup(replacing: .newItem) { }
        }
    }
}
