import AthkarCore
import SwiftUI

@main
struct AthkarApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("بكرة وأصيلا")
            .font(.largeTitle)
            .accessibilityIdentifier("title")
    }
}
