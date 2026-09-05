import Foundation

public struct CodexRunRequest: Sendable {
    public let workspaceURL: URL
    public let schemaURL: URL
    public let resultURL: URL
    public let model: String?
    public let effort: String?

    public init(
        workspaceURL: URL,
        schemaURL: URL,
        resultURL: URL,
        model: String? = nil,
        effort: String? = nil
    ) {
        self.workspaceURL = workspaceURL
        self.schemaURL = schemaURL
        self.resultURL = resultURL
        self.model = model
        self.effort = effort
    }
}

public enum CodexInvocationBuilder {
    public static func arguments(for request: CodexRunRequest) -> [String] {
        var arguments = [
            "--ask-for-approval", "never",
            "--sandbox", "read-only",
            "-C", request.workspaceURL.path,
            "-c", "project_doc_max_bytes=0",
            "-c", "skills.include_instructions=false",
            "-c", "include_apps_instructions=false",
            "-c", "include_permissions_instructions=false",
            "-c", "include_collaboration_mode_instructions=false",
            "-c", "web_search=\"disabled\"",
            "-c", "mcp_servers={}",
            "-c", "current_time_reminder=false",
        ]
        if let model = request.model {
            arguments += ["-m", model]
        }
        if let effort = request.effort {
            arguments += ["-c", "model_reasoning_effort=\"\(effort)\""]
        }
        arguments += [
            "exec",
            "--ephemeral",
            "--ignore-user-config",
            "--ignore-rules",
            "--skip-git-repo-check",
            "--color", "never",
            "--json",
            "--output-schema", request.schemaURL.path,
            "--output-last-message", request.resultURL.path,
            "-",
        ]
        return arguments
    }

    public static func arguments(
        workspaceURL: URL,
        schemaURL: URL,
        resultURL: URL
    ) -> [String] {
        arguments(for: CodexRunRequest(
            workspaceURL: workspaceURL,
            schemaURL: schemaURL,
            resultURL: resultURL
        ))
    }
}
