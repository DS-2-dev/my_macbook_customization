import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Are.na Widget")
                    .font(.title2.weight(.semibold))
                Text("This app only carries the widget. There is nothing else to do here.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Step(1, "Right-click the desktop and choose Edit Widgets.")
                Step(2, "Search for “Are.na”, pick a size, and drag it onto the desktop or into Notification Center.")
                Step(3, "Right-click the widget, choose Edit “Are.na Channel”, and paste a public channel’s slug or URL.")
            }
        }
        .padding(24)
        .frame(width: 440, alignment: .leading)
    }
}

private struct Step: View {
    let number: Int
    let text: String

    init(_ number: Int, _ text: String) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
