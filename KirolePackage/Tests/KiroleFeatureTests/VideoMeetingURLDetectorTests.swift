import Testing
import Foundation
@testable import KiroleFeature

// Tests for VideoMeetingURLDetector:
// - Detects Zoom, Google Meet, Teams, Lync URLs in description text
// - Detects from location field when description has no match
// - Returns nil for plain text with no video meeting URLs
// - isVideoMeetingURL correctly classifies known and unknown hosts

@Suite("VideoMeetingURLDetectorTests")
struct VideoMeetingURLDetectorTests {

    // MARK: - Known platform detection

    @Test("given text with Zoom URL, detect returns Zoom URL")
    func givenZoomURL_detectsIt() {
        let text = "Join the standup: https://zoom.us/j/12345678?pwd=abc"
        let url = VideoMeetingURLDetector.detect(in: text)
        #expect(url != nil)
        #expect(url?.host?.contains("zoom.us") == true)
    }

    @Test("given text with Zoom subdomain URL, detect returns it")
    func givenZoomSubdomainURL_detectsIt() {
        let text = "https://us02web.zoom.us/j/99999"
        let url = VideoMeetingURLDetector.detect(in: text)
        #expect(url != nil)
    }

    @Test("given text with Google Meet URL, detect returns Meet URL")
    func givenGoogleMeetURL_detectsIt() {
        let text = "Meet link: https://meet.google.com/abc-defg-hij"
        let url = VideoMeetingURLDetector.detect(in: text)
        #expect(url != nil)
        #expect(url?.host == "meet.google.com")
    }

    @Test("given text with Teams URL, detect returns Teams URL")
    func givenTeamsURL_detectsIt() {
        let text = "Microsoft Teams: https://teams.microsoft.com/l/meetup-join/19%3A..."
        let url = VideoMeetingURLDetector.detect(in: text)
        #expect(url != nil)
    }

    @Test("given text with Lync URL, detect returns Lync URL")
    func givenLyncURL_detectsIt() {
        let text = "https://meet.lync.com/company/user/ABCDEFGH"
        let url = VideoMeetingURLDetector.detect(in: text)
        #expect(url != nil)
    }

    // MARK: - Negative cases

    @Test("given plain text with no URLs, detect returns nil")
    func givenNoURL_returnsNil() {
        let url = VideoMeetingURLDetector.detect(in: "Team sync every Monday at 10am in the conference room.")
        #expect(url == nil)
    }

    @Test("given text with non-video URL, detect returns nil")
    func givenNonVideoURL_returnsNil() {
        let url = VideoMeetingURLDetector.detect(in: "See slides at https://docs.google.com/presentation/d/123")
        #expect(url == nil)
    }

    @Test("given nil text, detect returns nil")
    func givenNilText_returnsNil() {
        #expect(VideoMeetingURLDetector.detect(in: nil) == nil)
    }

    // MARK: - description + location fallback

    @Test("given description with no URL and location with Zoom URL, returns location URL")
    func givenLocationZoomURL_detectsFallback() {
        let url = VideoMeetingURLDetector.detect(
            description: "Weekly sync",
            location: "https://zoom.us/j/99887766"
        )
        #expect(url != nil)
    }

    @Test("given description with Meet URL and location with Zoom URL, returns description URL first")
    func givenBothDescriptionAndLocation_prefersDescription() {
        let url = VideoMeetingURLDetector.detect(
            description: "Join at https://meet.google.com/abc-defg-hij",
            location: "https://zoom.us/j/99887766"
        )
        #expect(url?.host == "meet.google.com")
    }

    // MARK: - isVideoMeetingURL

    @Test("given known video URL, isVideoMeetingURL returns true")
    func givenKnownURL_isVideoMeetingURLTrue() {
        let url = URL(string: "https://zoom.us/j/123")!
        #expect(VideoMeetingURLDetector.isVideoMeetingURL(url) == true)
    }

    @Test("given unknown URL, isVideoMeetingURL returns false")
    func givenUnknownURL_isVideoMeetingURLFalse() {
        let url = URL(string: "https://docs.google.com/document/d/1")!
        #expect(VideoMeetingURLDetector.isVideoMeetingURL(url) == false)
    }

    // MARK: - CalendarEvent integration

    @Test("given CalendarEvent with Zoom URL in description, videoMeetingURL is populated")
    func givenEventWithZoomDescription_videoURLPopulated() {
        let event = CalendarEvent(
            title: "Weekly sync",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            description: "Join: https://zoom.us/j/11223344",
            videoMeetingURL: VideoMeetingURLDetector.detect(
                description: "Join: https://zoom.us/j/11223344",
                location: nil
            )
        )
        #expect(event.videoMeetingURL != nil)
    }

    @Test("given CalendarEvent without video URL, videoMeetingURL is nil")
    func givenEventWithoutVideoURL_videoURLNil() {
        let event = CalendarEvent(
            title: "Lunch",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600)
        )
        #expect(event.videoMeetingURL == nil)
    }
}
