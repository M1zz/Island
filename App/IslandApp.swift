import SwiftUI

@main
struct IslandApp: App {
    var body: some Scene {
        WindowGroup("Unknown Island") {
            GameView()
        }
        .windowResizability(.contentSize)
    }
}
