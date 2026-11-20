import SwiftUI
import WidgetKit

@main
struct AlbumWidgetBundle: WidgetBundle {
    var body: some Widget {
        LastAlbumWidget()
    }
}

struct LastAlbumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: NowPlaying.widgetKind, provider: AlbumProvider()) { entry in
            AlbumWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Last Album")
        .description("The album you played last.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        // The view sets its own thin frame around the cover.
        .contentMarginsDisabled()
    }
}
