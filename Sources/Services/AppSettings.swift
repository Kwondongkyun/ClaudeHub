import Foundation
import SwiftUI

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("selectedTerminal") var selectedTerminal: String = TerminalApp.terminal.rawValue
    @AppStorage("refreshInterval") var refreshInterval: Double = 10

    var terminal: TerminalApp {
        get { TerminalApp(rawValue: selectedTerminal) ?? .terminal }
        set { selectedTerminal = newValue.rawValue }
    }

    var availableTerminals: [TerminalApp] {
        TerminalApp.allCases.filter(\.isInstalled)
    }
}
