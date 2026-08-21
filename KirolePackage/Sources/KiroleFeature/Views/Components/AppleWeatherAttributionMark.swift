import SwiftUI

/// Displays the unmodified Apple Weather mark returned by WeatherKit.
/// The provider name keeps attribution visible while the remote asset loads.
struct AppleWeatherAttributionMark: View {
    let markURLString: String?
    let serviceName: String
    let height: CGFloat
    let fallbackFont: Font
    let fallbackColor: Color

    var body: some View {
        Group {
            if let markURLString,
               let markURL = URL(string: markURLString) {
                AsyncImage(url: markURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        fallbackLabel
                    }
                }
            } else {
                fallbackLabel
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var fallbackLabel: some View {
        Text(serviceName.isEmpty ? "Weather" : serviceName)
            .font(fallbackFont)
            .foregroundStyle(fallbackColor)
            .lineLimit(1)
    }
}

/// Keeps WeatherKit attribution out of the compact header while leaving the
/// official mark and data-source link visible on the weather display page.
struct AppleWeatherAttributionFooter: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        if appState.weather.hasData,
           let legalURL = URL(string: appState.weather.attributionLegalURLString) {
            Link(destination: legalURL) {
                VStack(spacing: 3) {
                    AppleWeatherAttributionMark(
                        markURLString: appState.weather.attributionCombinedMarkLightURLString,
                        serviceName: appState.weather.attributionServiceName,
                        height: 10,
                        fallbackFont: .caption2,
                        fallbackColor: theme.colors.secondaryText
                    )

                    Text("Weather Data Sources")
                        .font(.caption2)
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .padding(.vertical, 12)
            }
            .accessibilityLabel("Apple Weather data sources")
            .accessibilityIdentifier("Home_WeatherAttribution")
        }
    }
}
