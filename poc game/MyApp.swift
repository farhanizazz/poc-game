import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView().frame(minWidth: 1050, minHeight: 720)
        }.defaultSize(width: 1280, height: 820)
        #else
        WindowGroup { IPhoneCompanionView() }
        #endif
    }
}
