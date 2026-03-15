import SwiftUI

class DisplayPreferences: ObservableObject {
    @AppStorage("costTrackingEnabled") var costTrackingEnabled = false
}
