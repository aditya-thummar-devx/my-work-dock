import SwiftUI

@main
struct MyWorkDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // No window scene: the NSPanel is created in AppDelegate.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
