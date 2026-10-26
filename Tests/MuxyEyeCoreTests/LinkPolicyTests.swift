import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct LinkPolicyTests {
    @Test func webLinksAreOpenable() {
        #expect(LinkPolicy.isOpenable(URL(string: "https://example.com/a?b=1")!))
        #expect(LinkPolicy.isOpenable(URL(string: "http://example.com")!))
        #expect(LinkPolicy.isOpenable(URL(string: "HTTPS://EXAMPLE.COM")!))
    }

    @Test func everythingElseIsRejected() {
        let rejected = [
            "javascript:alert(1)", "file:///etc/passwd", "data:text/html,hi", "x-apple.systempreferences:com.apple",
            "x-apple-reminder://", "mailto:a@b.c", "ssh://host", "/relative/path", "relative.html", "//example.com"
        ]
        for string in rejected {
            let url = URL(string: string)!
            #expect(!LinkPolicy.isOpenable(url), "\(string)")
        }
    }

    @Test func linksAreKeptOnlyWhenEnabledAndOpenable() {
        let web = URL(string: "https://example.com")!
        #expect(LinkPolicy.keeps(web, linksEnabled: true))
        #expect(!LinkPolicy.keeps(web, linksEnabled: false))
        #expect(!LinkPolicy.keeps(URL(string: "file:///x")!, linksEnabled: true))
    }
}
