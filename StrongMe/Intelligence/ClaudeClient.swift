//
//  ClaudeClient.swift
//  StrongMe
//
//  Minimal Messages API client (no Swift SDK exists, so raw HTTPS).
//  Uses claude-fable-5 with structured outputs so every parse comes back
//  as schema-valid JSON, plus the server-side fallback to claude-opus-4-8
//  so a rare safety-classifier decline is re-served instead of failing.
//

import Foundation

enum ClaudeError: Error, LocalizedError {
    case missingAPIKey
    case httpError(Int, String)
    case refusal
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No API key configured"
        case .httpError(let code, _): "The parsing service returned an error (\(code))"
        case .refusal: "The parsing service declined this request"
        case .emptyResponse: "The parsing service returned an empty response"
        }
    }
}

enum ClaudeClient {
    static let model = "claude-fable-5"
    static let fallbackModel = "claude-opus-4-8"

    /// Key lookup: scheme environment first (simulator dev), then a
    /// gitignored Secrets.plist in the bundle. Never hardcoded.
    static var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty {
            return env
        }
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url),
           let key = dict["ANTHROPIC_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return nil
    }

    static var isConfigured: Bool { apiKey != nil }

    /// One structured-output completion. Returns the raw JSON text that the
    /// schema guarantees is valid.
    static func completeJSON(system: String, user: String, schema: [String: Any]) async throws -> Data {
        guard let apiKey else { throw ClaudeError.missingAPIKey }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2000,
            "fallbacks": [["model": fallbackModel]],
            "output_config": [
                "effort": "low",  // parsing is routine work; keep it fast
                "format": ["type": "json_schema", "schema": schema],
            ],
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-06-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ClaudeError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.emptyResponse
        }
        if json["stop_reason"] as? String == "refusal" {
            throw ClaudeError.refusal
        }
        guard let content = json["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let textData = text.data(using: .utf8) else {
            throw ClaudeError.emptyResponse
        }
        return textData
    }
}
