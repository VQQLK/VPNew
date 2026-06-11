import SwiftUI

@main
struct MyVPNApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 360, idealWidth: 360, maxWidth: 400,
                       minHeight: 520, idealHeight: 520, maxHeight: 600)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }  // убираем "New Window"
        }
    }
}
