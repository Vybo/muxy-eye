import Foundation

public struct QuestionOption: Sendable, Equatable {
    public let label: String
    public let description: String?
}

public struct Question: Sendable, Equatable {
    public let question: String
    public let header: String
    public let options: [QuestionOption]
    public let multiSelect: Bool
}

public struct QuestionRequest: Sendable, Equatable {
    public let questions: [Question]
    /// The `tool_use_id` of the `AskUserQuestion` call, which its `PostToolUse` repeats.
    public let toolUseID: String?

    public init(questions: [Question], toolUseID: String? = nil) {
        self.questions = questions
        self.toolUseID = toolUseID
    }
}

public struct PermissionRequest: Sendable, Equatable {
    public let toolName: String
    public let toolInput: JSONValue
    /// Set when a subagent asks. Claude sends `agent_id` only for tool calls inside a subagent.
    public let agentID: String?

    public init(toolName: String, toolInput: JSONValue, agentID: String? = nil) {
        self.toolName = toolName
        self.toolInput = toolInput
        self.agentID = agentID
    }

    public var title: String {
        switch toolName {
        case "Bash": "Bash command"
        case "Write": "Create file"
        case "Edit", "MultiEdit": "Edit file"
        case "WebFetch": "Fetch"
        default: toolName
        }
    }

    public var primaryText: String? {
        for key in ["command", "file_path", "url", "pattern"] {
            if let value = toolInput[key]?.stringValue { return value }
        }
        return nil
    }

    public var detail: String? {
        toolInput["description"]?.stringValue
    }
}

/// A finished tool call, from `PostToolUse`.
public struct ToolUse: Sendable, Equatable {
    public let toolName: String
    public let toolInput: JSONValue
    public let toolUseID: String?
    public let agentID: String?

    public init(toolName: String, toolInput: JSONValue, toolUseID: String?, agentID: String?) {
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolUseID = toolUseID
        self.agentID = agentID
    }
}

public enum ClaudeHookEvent: Sendable, Equatable {
    case sessionStart(claudeSessionID: String)
    case sessionEnd
    case userPromptSubmit
    case permission(PermissionRequest)
    case question(QuestionRequest)
    case postToolUse(ToolUse)
    case notification(type: String, message: String)
    case stop(lastAssistantMessage: String?)
}

public struct HookEvent: Sendable, Equatable {
    public let muxySession: MuxySessionID
    public let claudeSessionID: String?
    public let event: ClaudeHookEvent
}

public enum HookDecoder {
    static let askUserQuestion = "AskUserQuestion"

    public static func decode(_ envelope: HookEnvelope) -> HookEvent? {
        let payload = envelope.payload
        let claudeSessionID = payload["session_id"]?.stringValue
        guard let event = decodeEvent(name: envelope.event, payload: payload, claudeSessionID: claudeSessionID) else {
            return nil
        }
        return HookEvent(muxySession: envelope.muxySessionID, claudeSessionID: claudeSessionID, event: event)
    }

    private static func decodeEvent(name: String, payload: JSONValue, claudeSessionID: String?) -> ClaudeHookEvent? {
        let toolName = payload["tool_name"]?.stringValue
        let toolUseID = payload["tool_use_id"]?.stringValue
        let agentID = payload["agent_id"]?.stringValue
        switch name {
        case "SessionStart":
            return claudeSessionID.map { .sessionStart(claudeSessionID: $0) }
        case "SessionEnd":
            return .sessionEnd
        case "UserPromptSubmit":
            return .userPromptSubmit
        case "PermissionRequest":
            guard let toolName, toolName != askUserQuestion else { return nil }
            return .permission(PermissionRequest(toolName: toolName, toolInput: payload["tool_input"] ?? .null, agentID: agentID))
        case "PreToolUse":
            guard toolName == askUserQuestion, let input = payload["tool_input"] else { return nil }
            return .question(decodeQuestions(input, toolUseID: toolUseID))
        case "PostToolUse":
            guard let toolName else { return nil }
            return .postToolUse(ToolUse(
                toolName: toolName,
                toolInput: payload["tool_input"] ?? .null,
                toolUseID: toolUseID,
                agentID: agentID
            ))
        case "Notification":
            return .notification(
                type: payload["notification_type"]?.stringValue ?? "",
                message: payload["message"]?.stringValue ?? ""
            )
        case "Stop":
            return .stop(lastAssistantMessage: payload["last_assistant_message"]?.stringValue)
        default:
            return nil
        }
    }

    private static func decodeQuestions(_ input: JSONValue, toolUseID: String?) -> QuestionRequest {
        let questions = (input["questions"]?.arrayValue ?? []).compactMap { item -> Question? in
            guard let text = item["question"]?.stringValue else { return nil }
            let options = (item["options"]?.arrayValue ?? []).compactMap { option -> QuestionOption? in
                guard let label = option["label"]?.stringValue else { return nil }
                return QuestionOption(label: label, description: option["description"]?.stringValue)
            }
            return Question(
                question: text,
                header: item["header"]?.stringValue ?? "",
                options: options,
                multiSelect: item["multiSelect"]?.boolValue ?? false
            )
        }
        return QuestionRequest(questions: questions, toolUseID: toolUseID)
    }
}
