import SwiftUI

@main
struct StevoraApp: App {
    @StateObject private var model = StevoraModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}
