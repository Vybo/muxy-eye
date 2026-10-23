public struct ScreenOption: Sendable, Equatable {
    public var number: Int
    public var label: String
    public var description: String?
    public var isCursor: Bool
    public var checked: Bool?

    public init(number: Int, label: String, description: String?, isCursor: Bool, checked: Bool?) {
        self.number = number
        self.label = label
        self.description = description
        self.isCursor = isCursor
        self.checked = checked
    }
}

public enum ScreenPrompt: Sendable, Equatable {
    case permission(title: String, body: String, question: String, options: [ScreenOption])
    case question(header: String, question: String, options: [ScreenOption], isMultiSelect: Bool)
    case submitReview(options: [ScreenOption])
}
