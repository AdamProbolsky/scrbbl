import CoreText
import SwiftUI

@main
struct ScrbblApp: App {
    init() {
        // Answers are drawn in a bundled handwriting font (SIL Open Font License,
        // see Fonts/OFL.txt). Registering at launch avoids an Info.plist entry.
        if let url = Bundle.main.url(forResource: "NothingYouCouldDo", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
