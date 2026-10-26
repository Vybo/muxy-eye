import Testing
@testable import MuxyEyeCore

@Suite struct MarkdownBlocksTests {
    @Test func emptyTextHasNoBlocks() {
        #expect(MarkdownBlocks.parse("").isEmpty)
        #expect(MarkdownBlocks.parse("\n  \n\n").isEmpty)
    }

    @Test func plainTextIsOneParagraph() {
        #expect(MarkdownBlocks.parse("Just **this**.") == [.paragraph("Just **this**.")])
    }

    @Test func blankLinesSplitParagraphsAndLinesStayTogether() {
        let blocks = MarkdownBlocks.parse("one\ntwo\n\n\nthree")
        #expect(blocks == [.paragraph("one\ntwo"), .paragraph("three")])
    }

    @Test func windowsLineEndingsAreHandled() {
        #expect(MarkdownBlocks.parse("a\r\n\r\nb") == [.paragraph("a"), .paragraph("b")])
    }

    @Test func headingsKeepTheirLevel() {
        let blocks = MarkdownBlocks.parse("# One\n## Two\n### Three **x**")
        #expect(blocks == [
            .heading(level: 1, text: "One"),
            .heading(level: 2, text: "Two"),
            .heading(level: 3, text: "Three **x**")
        ])
    }

    @Test func hashWithoutSpaceIsNotAHeading() {
        #expect(MarkdownBlocks.parse("#hashtag") == [.paragraph("#hashtag")])
        #expect(MarkdownBlocks.parse("####### seven") == [.paragraph("####### seven")])
    }

    @Test func headingEndsAParagraph() {
        #expect(MarkdownBlocks.parse("intro\n# Title\nbody") == [
            .paragraph("intro"), .heading(level: 1, text: "Title"), .paragraph("body")
        ])
    }

    @Test func bulletMarkersAreAllRecognised() {
        let blocks = MarkdownBlocks.parse("- a\n* b\n+ c")
        #expect(blocks == [
            .listItem(depth: 0, marker: .bullet, text: "a"),
            .listItem(depth: 0, marker: .bullet, text: "b"),
            .listItem(depth: 0, marker: .bullet, text: "c")
        ])
    }

    @Test func numberedItemsKeepTheirNumbers() {
        let blocks = MarkdownBlocks.parse("1. first\n2. second\n10) tenth")
        #expect(blocks == [
            .listItem(depth: 0, marker: .number(1), text: "first"),
            .listItem(depth: 0, marker: .number(2), text: "second"),
            .listItem(depth: 0, marker: .number(10), text: "tenth")
        ])
    }

    @Test func indentedItemsNestOneLevel() {
        let blocks = MarkdownBlocks.parse("- a\n  - b\n      - c\n\t- d\n- e")
        #expect(blocks == [
            .listItem(depth: 0, marker: .bullet, text: "a"),
            .listItem(depth: 1, marker: .bullet, text: "b"),
            .listItem(depth: 1, marker: .bullet, text: "c"),
            .listItem(depth: 1, marker: .bullet, text: "d"),
            .listItem(depth: 0, marker: .bullet, text: "e")
        ])
    }

    @Test func indentedLineContinuesItsItem() {
        #expect(MarkdownBlocks.parse("- one\n  more\n- two") == [
            .listItem(depth: 0, marker: .bullet, text: "one\nmore"),
            .listItem(depth: 0, marker: .bullet, text: "two")
        ])
    }

    @Test func dashWithoutSpaceIsNotAnItem() {
        #expect(MarkdownBlocks.parse("-5 degrees") == [.paragraph("-5 degrees")])
    }

    @Test func listItemEndsAParagraph() {
        #expect(MarkdownBlocks.parse("Steps:\n- a") == [
            .paragraph("Steps:"), .listItem(depth: 0, marker: .bullet, text: "a")
        ])
    }

    @Test func fencedCodeKeepsItsLinesVerbatim() {
        let text = "before\n```swift\nlet a = 1\n\n  # not a heading\n- not a list\n```\nafter"
        #expect(MarkdownBlocks.parse(text) == [
            .paragraph("before"),
            .codeBlock(language: "swift", code: "let a = 1\n\n  # not a heading\n- not a list"),
            .paragraph("after")
        ])
    }

    @Test func fenceWithoutLanguageHasNone() {
        #expect(MarkdownBlocks.parse("```\nls\n```") == [.codeBlock(language: nil, code: "ls")])
    }

    @Test func unclosedFenceRunsToTheEnd() {
        #expect(MarkdownBlocks.parse("```\nstill\ncoding") == [.codeBlock(language: nil, code: "still\ncoding")])
    }

    @Test func emptyFenceIsAnEmptyCodeBlock() {
        #expect(MarkdownBlocks.parse("```\n```") == [.codeBlock(language: nil, code: "")])
    }

    @Test func quoteLinesJoinAndLoseTheirMarker() {
        #expect(MarkdownBlocks.parse("> one\n>two\n> \n> three") == [.quote("one\ntwo\n\nthree")])
    }

    @Test func quoteEndsAtABlankLine() {
        #expect(MarkdownBlocks.parse("> q\n\nafter") == [.quote("q"), .paragraph("after")])
    }

    @Test func rulesNeedThreeOfTheSameCharacter() {
        #expect(MarkdownBlocks.parse("---\n***\n___\n- - -") == [.rule, .rule, .rule, .rule])
        #expect(MarkdownBlocks.parse("--") == [.paragraph("--")])
        #expect(MarkdownBlocks.parse("-*-") == [.paragraph("-*-")])
    }

    @Test func ruleBetweenParagraphs() {
        #expect(MarkdownBlocks.parse("a\n\n---\n\nb") == [.paragraph("a"), .rule, .paragraph("b")])
    }

    @Test func aMixedMessage() {
        let text = """
        ## Done

        I changed **two** files:

        1. `a.swift`
        2. `b.swift`
           - detail

        > note

        ```
        swift test
        ```
        """
        #expect(MarkdownBlocks.parse(text) == [
            .heading(level: 2, text: "Done"),
            .paragraph("I changed **two** files:"),
            .listItem(depth: 0, marker: .number(1), text: "`a.swift`"),
            .listItem(depth: 0, marker: .number(2), text: "`b.swift`"),
            .listItem(depth: 1, marker: .bullet, text: "detail"),
            .quote("note"),
            .codeBlock(language: nil, code: "swift test")
        ])
    }
}
