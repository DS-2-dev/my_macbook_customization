import SwiftUI
import WidgetKit

@main
struct ArenaWidgetBundle: WidgetBundle {
    var body: some Widget {
        ChannelWidget()
    }
}

struct ChannelWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "ArenaChannelWidget",
            intent: ChannelConfigurationIntent.self,
            provider: ChannelProvider()
        ) { entry in
            ChannelWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Are.na Channel")
        .description("Recent blocks from an Are.na channel.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        // The grid sets its own thin margin so the tiles fill the widget.
        .contentMarginsDisabled()
    }
}
