@testable import MuxyEyeCore

/// The questions behind `screens/question-multiline.txt` (several paragraphs) and
/// `screens/question-wrapped.txt` (one paragraph the terminal wraps), exactly as Claude's hook sent them.
extension Fixture {
    static let multilineQuestion = Question(
        question: "Plan for the next fixes. This question is long and has several paragraphs on purpose, so I can capture how the terminal draws it for the matching fix (the eye will show no options for it yet).\n\nFlash: closing hides the panel's window and shows it again to give the keyboard back to your other app. That is why the panel and the eye vanish for a moment. The fix hands the keyboard back through an invisible helper window instead, so the visible window never leaves the screen.\n\nQuestions: the eye will compare a question with all of its lines on the screen, ignoring where the terminal wraps them, instead of with only the first line.\n\nAfter that, a tall prompt with a one-line question to test the scrolling. Go ahead?",
        header: "Next fixes",
        options: [
            QuestionOption(label: "Go ahead", description: "Fix both the close flash and the question matching, then build build-next3 and send the scroll test prompt."),
            QuestionOption(label: "Flash fix only", description: "Fix only the close flash for now; leave the question matching as it is."),
            QuestionOption(label: "Matching fix only", description: "Fix only the question matching for now; leave the close flash as it is."),
            QuestionOption(label: "Wait", description: "Don't change anything yet.")
        ],
        multiSelect: false
    )

    static let wrappedQuestion = Question(
        question: "Capture only, no decision needed: this is one long paragraph without line breaks, so the terminal has to wrap it, and it has **bold text** and `inline code` in it to see whether the terminal draws the markdown or shows the asterisks and backticks as they are; in the eye this question will show without options until the matching fix lands. Pick any option.",
        header: "Capture",
        options: [
            QuestionOption(label: "Done", description: "Nothing happens; the screen was captured."),
            QuestionOption(label: "Eye shows raw marks", description: "The eye's panel shows the asterisks or backticks instead of bold and code.")
        ],
        multiSelect: false
    )
}
