import AppIntents
import ArenaKit
import WidgetKit

struct ChannelConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Channel"
    static let description = IntentDescription("Choose the Are.na channel this widget shows.")

    /// The part of a channel URL after the username, e.g. are.na/dante-smith/**inspo-syd5sijpqmk**.
    /// Pasting the whole URL works too. The default must stay a literal for
    /// App Intents metadata extraction; keep it in sync with `ChannelSlug.fallback`.
    @Parameter(title: "Channel", description: "Channel slug or URL", default: "inspo-syd5sijpqmk")
    var channelSlug: String

    @Parameter(title: "Show Titles", default: false)
    var showTitles: Bool

    var slug: String {
        let slug = ChannelSlug.normalize(channelSlug)
        return slug.isEmpty ? ChannelSlug.fallback : slug
    }
}
