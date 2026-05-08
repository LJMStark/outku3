import SwiftUI

/// Apple Weather attribution badge required when displaying WeatherKit data.
///
/// Apple's WeatherKit Terms (App Store Review Guideline 5.2.5) require that any UI
/// surfacing WeatherKit data must clearly display:
///   1. The Apple Weather trademark (" Weather")
///   2. A user-tappable link to https://weatherkit.apple.com/legal-attribution.html
///
/// This view satisfies both in a single tappable badge sized to fit alongside
/// the temperature chip in the home header.
struct WeatherAttributionView: View {
    private static let legalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    var body: some View {
        Link(destination: Self.legalURL) {
            Text("\u{F8FF} Weather")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .underline()
        }
        .accessibilityLabel("Apple Weather attribution")
        .accessibilityHint("Opens Apple Weather legal data sources")
        .accessibilityIdentifier("appHeader.weatherAttribution")
    }
}

#Preview {
    WeatherAttributionView()
        .padding()
        .background(Color(red: 0.4, green: 0.6, blue: 0.85))
}
