import SwiftUI

@main
struct BubblIOSCanaryApp: App {
    @StateObject private var model = CanaryViewModel()

    var body: some Scene {
        WindowGroup {
            CanaryView(model: model)
                .task {
                    await model.runIfNeeded()
                }
        }
    }
}
