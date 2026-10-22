import Foundation

struct QuestionOption: Codable, Equatable, Hashable {
    var label: String
    var description: String?
}

struct AgentQuestion: Codable, Equatable {
    var question: String
    var header: String?
    var options: [QuestionOption]
    var multiSelect: Bool

    init(question: String, header: String? = nil, options: [QuestionOption], multiSelect: Bool) {
        self.question = question; self.header = header; self.options = options; self.multiSelect = multiSelect
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        question = try c.decode(String.self, forKey: .question)
        header = try c.decodeIfPresent(String.self, forKey: .header)
        options = try c.decodeIfPresent([QuestionOption].self, forKey: .options) ?? []
        multiSelect = try c.decodeIfPresent(Bool.self, forKey: .multiSelect) ?? false
    }
}

struct QuestionAnswer: Equatable {
    var question: String
    var answer: String
}

/// What the user decided about a pending request.
enum AgentDecision: Equatable {
    case allow(always: Bool)
    case deny(reason: String?)
    /// Let the agent show its own prompt.
    case passthrough
    case answer([QuestionAnswer])
    /// Deliver a prompt typed in MyWorkDock (wakes an idle session).
    case send(String)
}

/// Agent-neutral events produced by adapters.
enum AgentEvent: Equatable {
    case sessionStarted, sessionEnded, idle
    case prompt(String)
    case toolStarted(tool: String, input: JSONValue)
    case toolFinished(tool: String)
    case permission(tool: String, input: JSONValue)
    case question([AgentQuestion])
    case notification(String)
    /// The background wake hook is ready to deliver a prompt.
    case awaitingPrompt
}

enum AgentState: String, Equatable {
    case working, waiting, idle, ended

    var label: String {
        switch self {
        case .working: "Working"
        case .waiting: "Waiting for you"
        case .idle: "Idle"
        case .ended: "Ended"
        }
    }
}

struct AgentSession: Identifiable, Equatable {
    var id: String          // "claude:<session id>"
    var agent: String
    var cwd: String?
    var project: String
    var state: AgentState
    var lastAction: String?
    var updatedAt: Date
    var tty: String?
    /// The `claude` process that owns `tty`; gone means the session is over.
    var ownerPID: Int32?
    /// Terminal app ("Terminal", "Warp", …) from TERM_PROGRAM.
    var terminal: String?
    /// A wake hook is waiting: a prompt reaches this idle session at once.
    var reachable = false
    var queued = 0

    var canTypeInto: Bool { terminal == nil || terminal == "Terminal" || terminal == "iTerm2" }
    /// Claude's own session id (the transcript file name).
    var transcriptID: String { id.hasPrefix("claude:") ? String(id.dropFirst(7)) : id }
}

enum PendingKind: Equatable {
    case permission(tool: String, input: JSONValue)
    case question([AgentQuestion])
}

struct PendingRequest: Identifiable, Equatable {
    var id: String
    var agent: String
    var sessionID: String
    var project: String
    var kind: PendingKind
    var createdAt: Date
}

/// "Always allow" for one tool in one project; for shell tools, only the exact command.
struct AlwaysRule: Codable, Equatable, Hashable {
    var agent: String
    var tool: String
    var cwd: String?
    var command: String?

    static let commandScoped: Set<String> = ["Bash", "PowerShell"]

    static func forRequest(agent: String, tool: String, input: JSONValue, cwd: String?) -> AlwaysRule {
        AlwaysRule(agent: agent, tool: tool, cwd: cwd, command: commandScoped.contains(tool) ? (input["command"]?.string ?? "") : nil)
    }

    func matches(agent: String, tool: String, input: JSONValue, cwd: String?) -> Bool {
        self.agent == agent && self.tool == tool && cwd != nil && self.cwd == cwd
            && (command == nil || input["command"]?.string == command)
    }
}

func projectName(_ cwd: String?) -> String {
    guard let cwd, !cwd.isEmpty else { return "unknown" }
    return URL(fileURLWithPath: cwd).lastPathComponent
}

func terminalName(_ termProgram: String) -> String {
    switch termProgram {
    case "Apple_Terminal": "Terminal"
    case "iTerm.app": "iTerm2"
    case "WarpTerminal": "Warp"
    case "vscode": "VS Code"
    case "ghostty": "Ghostty"
    default: termProgram
    }
}
