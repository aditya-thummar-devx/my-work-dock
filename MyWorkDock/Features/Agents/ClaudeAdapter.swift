import Foundation

/// Claude Code's hook vocabulary (https://code.claude.com/docs/en/hooks) to and from MyWorkDock's.
enum ClaudeAdapter {
    static let denyMessage = "Denied from MyWorkDock"

    static func sessionID(_ m: HookMessage) -> String {
        if let id = m.payload["session_id"]?.string { return "claude:\(id)" }
        return "claude:\(m.pid ?? 0):\(m.cwd ?? "")"
    }

    static func events(_ m: HookMessage) -> [AgentEvent] {
        let tool = m.payload["tool_name"]?.string ?? ""
        let input = m.payload["tool_input"] ?? .null
        switch m.event {
        case "SessionStart": return [.sessionStarted]
        case "SessionEnd": return [.sessionEnded]
        case "UserPromptSubmit": return [.prompt(m.payload["prompt"]?.string ?? "")]
        case "PreToolUse" where tool == "AskUserQuestion": return [.question(questions(input))]
        case "PreToolUse": return [.toolStarted(tool: tool, input: input)]
        case "PostToolUse": return [.toolFinished(tool: tool)]
        // Questions are answered through PreToolUse; a second card here would carry no answers.
        case "PermissionRequest" where tool == "AskUserQuestion": return []
        case "PermissionRequest": return [.permission(tool: tool, input: input)]
        case "Notification": return [.notification(m.payload["message"]?.string ?? "")]
        case "Stop": return [.idle]
        case "Wake": return [.awaitingPrompt]
        default: return []
        }
    }

    static func questions(_ input: JSONValue) -> [AgentQuestion] {
        guard let q = input["questions"], let data = try? JSONEncoder().encode(q) else { return [] }
        return (try? JSONDecoder().decode([AgentQuestion].self, from: data)) ?? []
    }

    /// Stdout and exit code `mwd-hook` should produce.
    static func reply(_ m: HookMessage, _ d: AgentDecision) -> (String, Int32) {
        func json(_ v: JSONValue) -> (String, Int32) {
            (String(decoding: (try? JSONEncoder().encode(v)) ?? Data(), as: UTF8.self), 0)
        }
        func hso(_ fields: [String: JSONValue]) -> JSONValue { .object(["hookSpecificOutput": .object(fields)]) }
        switch (m.event, d) {
        case ("PermissionRequest", .allow):
            return json(hso(["hookEventName": .string("PermissionRequest"), "decision": .object(["behavior": .string("allow")])]))
        case ("PermissionRequest", .deny(let reason)):
            return json(hso(["hookEventName": .string("PermissionRequest"),
                             "decision": .object(["behavior": .string("deny"), "message": .string(reason ?? denyMessage)])]))
        case ("PreToolUse", .answer(let answers)):
            // AskUserQuestion is answered by allowing it with the original input plus `answers`.
            var input = (m.payload["tool_input"]?.object) ?? [:]
            input["answers"] = .object(Dictionary(answers.map { ($0.question, JSONValue.string($0.answer)) }, uniquingKeysWith: { a, _ in a }))
            return json(hso(["hookEventName": .string("PreToolUse"), "permissionDecision": .string("allow"), "updatedInput": .object(input)]))
        case ("PreToolUse", .deny(let reason)):
            return json(hso(["hookEventName": .string("PreToolUse"), "permissionDecision": .string("deny"),
                             "permissionDecisionReason": .string(reason ?? denyMessage)]))
        case ("Wake", .send(let prompt)):
            // asyncRewake: exit code 2 wakes Claude; the hook's output is shown to it.
            return ("The user sent this message from MyWorkDock. Treat it as their next message:\n\n\(prompt)", 2)
        default:
            return ("", 0)
        }
    }
}
