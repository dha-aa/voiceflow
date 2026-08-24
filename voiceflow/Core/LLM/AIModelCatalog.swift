//
//  AIModelCatalog.swift
//  VoiceFlow
//
//  Provider model discovery for AI Settings.
//

import Foundation

struct LiveClaudeModelCatalogClient: AIModelCatalogClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/models")!
    private static let anthropicVersion = "2023-06-01"

    private struct ResponseBody: Decodable {
        let data: [Model]
    }

    private struct Model: Decodable {
        let id: String
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    func fetchModels(apiKey: String) async throws -> [AIModel] {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIModelCatalogError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIModelCatalogError.httpStatus(httpResponse.statusCode)
        }

        return try Self.decodeModels(from: data)
    }

    static func decodeModels(from data: Data) throws -> [AIModel] {
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let models = decoded.data
            .map { AIModel(id: $0.id, displayName: $0.displayName) }
            .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        guard !models.isEmpty else {
            throw AIModelCatalogError.emptyModelList
        }
        return models
    }
}

enum AIModelCatalogError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case emptyModelList
}
