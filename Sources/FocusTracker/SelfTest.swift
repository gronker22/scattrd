import Foundation

/// Tiny runtime self-test for the pure logic that's otherwise hard to verify
/// without live browser permissions. Run with `FOCUSTRACKER_SELFTEST=1`.
enum SelfTest {
    static func run() {
        let samples = [
            "https://www.youtube.com/watch?v=abc",
            "https://github.com/owner/repo/pull/3",
            "https://mail.google.com/mail/u/0/#inbox",
            "https://twitter.com/home",
            "https://x.com/explore",
            "https://docs.google.com/document/d/xyz",
            "https://stackoverflow.com/questions/42",
            "https://reddit.com/r/swift",
            "https://app.slack.com/client/T1",
            "http://localhost:3000/dashboard",
            "https://www.google.com/search?q=swift",
            "chrome://settings/passwords",
            "https://watchluna.com/movie/inception",
            "https://freeslots-casino.net/play",
            "https://coolmathgames.com/0-run",
            "https://streamlit.io/docs",
        ]
        print("DOMAIN EXTRACTION + CATEGORIZATION")
        print(String(repeating: "-", count: 52))
        for url in samples {
            let host = BrowserTabReader.host(from: url)
            let label = host ?? "(non-web → fall back to app)"
            let cat = host.map { AppCatalog.categoryForDomain($0).label } ?? "—"
            print("  " + label.padding(toLength: 34, withPad: " ", startingAt: 0) + "→ " + cat)
        }
    }
}
