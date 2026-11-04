import XCTest
@testable import PocketCore

final class RichReplyTests: XCTestCase {
    func testPlainTextIsOneUntouchedProseSegment() {
        let text = "Remind me to call Mom at 7.\n\n  Two  lines, with spacing."
        XCTAssertEqual(RichReply.segments(text), [.prose(text)])
    }

    func testAngleBracketsInProseAreNotMarkup() {
        for text in ["3 < 5 and 7 > 2", "Use <b>bold</b> in your note", "Reply to <dana@example.com>",
                     "<svg width=1> is how an icon starts", "Here: <html> then some words but no end"] {
            XCTAssertEqual(RichReply.segments(text), [.prose(text)], text)
            XCTAssertFalse(RichReply.containsMarkup(text), text)
        }
    }

    func testFencedHTMLBetweenProseKeepsBothSides() {
        let text = "Here is your chart.\n\n```html\n<svg viewBox=\"0 0 10 10\"><rect width=\"5\" height=\"5\"/></svg>\n```\n\nBars are in dollars."
        XCTAssertEqual(RichReply.segments(text), [
            .prose("Here is your chart."),
            .markup(EmbeddedMarkup(kind: .html, source: "<svg viewBox=\"0 0 10 10\"><rect width=\"5\" height=\"5\"/></svg>")),
            .prose("Bars are in dollars."),
        ])
    }

    func testFencedSVGKindAndTildeFenceAndCaseInsensitiveTag() {
        let svg = "<svg><circle r=\"4\"/></svg>"
        XCTAssertEqual(RichReply.segments("```SVG\n\(svg)\n```"), [.markup(EmbeddedMarkup(kind: .svg, source: svg))])
        XCTAssertEqual(RichReply.segments("~~~html\n<p>hi</p>\n~~~"), [.markup(EmbeddedMarkup(kind: .html, source: "<p>hi</p>"))])
    }

    func testSVGFenceWithoutSVGRootStaysProse() {
        let text = "```svg\njust words\n```"
        XCTAssertEqual(RichReply.segments(text), [.prose(text)])
    }

    func testOtherLanguagesAndUnterminatedFencesStayProse() {
        let swift = "```swift\nlet x = \"<b>\"\n```"
        XCTAssertEqual(RichReply.segments(swift), [.prose(swift)])
        let open = "Intro\n```html\n<p>cut off"
        XCTAssertEqual(RichReply.segments(open), [.prose(open)])
    }

    func testIndentedFourSpacesIsNotAFence() {
        let text = "    ```html\n    <p>x</p>\n    ```"
        XCTAssertEqual(RichReply.segments(text), [.prose(text)])
    }

    func testWholeReplyDocumentsAreMarkupButMixedUnfencedIsNot() {
        let page = "<!DOCTYPE html><html><body><p>x</p></body></html>"
        XCTAssertEqual(RichReply.segments("\n" + page + "\n"), [.markup(EmbeddedMarkup(kind: .html, source: page))])
        let svg = "<svg viewBox=\"0 0 1 1\"></svg>"
        XCTAssertEqual(RichReply.segments(svg), [.markup(EmbeddedMarkup(kind: .svg, source: svg))])
        let mixed = "Here you go: " + page
        XCTAssertEqual(RichReply.segments(mixed), [.prose(mixed)])
    }

    func testOversizeBlockStaysProseAndDocumentCountIsCapped() {
        let big = "```html\n<p>" + String(repeating: "a", count: RichReply.maxDocumentBytes) + "</p>\n```"
        XCTAssertFalse(RichReply.containsMarkup(big))
        let many = (0..<6).map { "```html\n<p>\($0)</p>\n```" }.joined(separator: "\n")
        let docs = RichReply.segments(many).filter { if case .markup = $0 { return true } else { return false } }
        XCTAssertEqual(docs.count, RichReply.maxDocuments)
    }

    func testCRLFIsHandled() {
        XCTAssertEqual(RichReply.segments("a\r\n```html\r\n<p>x</p>\r\n```\r\nb"), [
            .prose("a"), .markup(EmbeddedMarkup(kind: .html, source: "<p>x</p>")), .prose("b")])
    }

    func testFencedHelperSurvivesBackticksInContent() {
        let source = "<h1>```not a fence```</h1>\n<p>` ``` ````</p>"
        let reply = "Chart ready: 2 bars\n\n" + RichReply.fenced(source)
        XCTAssertEqual(RichReply.segments(reply), [.prose("Chart ready: 2 bars"), .markup(EmbeddedMarkup(kind: .html, source: source))])
    }

    func testHTMLVizOutputRoundTripsThroughTheFence() throws {
        let r = try XCTUnwrap(HTMLViz.render(text: "rent 1200, food 400", title: "Budget ```x"))
        let reply = "Chart ready: \(r.bars) bars, drawn on device\n\n" + RichReply.fenced(r.html)
        let segs = RichReply.segments(reply)
        XCTAssertEqual(segs.count, 2)
        guard case .markup(let m) = segs[1] else { return XCTFail("chart must be markup") }
        XCTAssertEqual(m.source, r.html.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testPageCarriesRestrictiveCSPAndKeepsHostileSourceVerbatimForTheRenderer() {
        let hostile = "<img src=\"https://evil.example/p.png\"><link rel=\"stylesheet\" href=\"https://evil.example/s.css\"><form action=\"https://evil.example\"></form>"
        let page = RichReply.page(for: EmbeddedMarkup(kind: .html, source: hostile))
        XCTAssertTrue(page.contains("Content-Security-Policy"))
        XCTAssertTrue(page.contains("default-src 'none'"))
        XCTAssertTrue(page.contains("form-action 'none'"))
        XCTAssertTrue(page.contains("base-uri 'none'"))
        XCTAssertTrue(page.contains(hostile))
        let csp = page.range(of: "Content-Security-Policy")!.lowerBound
        XCTAssertLessThan(page.distance(from: page.startIndex, to: csp), page.distance(from: page.startIndex, to: page.range(of: hostile)!.lowerBound))
    }
}
