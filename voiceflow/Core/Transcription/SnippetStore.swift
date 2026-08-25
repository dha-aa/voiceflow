import Foundation
import Observation

struct Snippet: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var trigger: String
    var value: String

    init(
        id: UUID = UUID(),
        name: String,
        trigger: String,
        value: String
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.value = value
    }
}

@Observable
final class SnippetStore {
    static let storageKey = "voiceFlowSnippets"

    private let userDefaults: UserDefaults
    private(set) var snippets: [Snippet]

    init(
        userDefaults: UserDefaults = .standard,
        snippets: [Snippet]? = nil
    ) {
        self.userDefaults = userDefaults
        if let snippets {
            self.snippets = snippets
        } else if let data = userDefaults.data(forKey: Self.storageKey),
                  let decoded = try? JSONDecoder().decode([Snippet].self, from: data) {
            self.snippets = decoded.filter(Self.isUsable)
        } else {
            self.snippets = []
        }
    }

    @discardableResult
    func add(name: String, trigger: String, value: String) -> UUID {
        let snippet = Snippet(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            trigger: trigger.trimmingCharacters(in: .whitespacesAndNewlines),
            value: value
        )
        guard Self.isUsable(snippet) else { return UUID() }
        snippets.append(snippet)
        persist()
        return snippet.id
    }

    func update(id: UUID, name: String, trigger: String, value: String) {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        let updated = Snippet(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            trigger: trigger.trimmingCharacters(in: .whitespacesAndNewlines),
            value: value
        )
        guard Self.isUsable(updated) else { return }
        snippets[index] = updated
        persist()
    }

    func delete(id: UUID) {
        snippets.removeAll { $0.id == id }
        persist()
    }

    /// Expands configured triggers locally. Values never enter an AI request.
    /// Matching is case-insensitive and requires non-word boundaries, so a
    /// trigger such as "my email" does not match inside "my emails".
    func expand(_ text: String) -> String {
        guard !text.isEmpty, !snippets.isEmpty else { return text }

        let candidates = snippets.flatMap { snippet -> [(NSRange, String)] in
            let escapedTrigger = NSRegularExpression.escapedPattern(for: snippet.trigger)
            guard let expression = try? NSRegularExpression(
                pattern: "(?<![\\p{L}\\p{N}_])\(escapedTrigger)(?![\\p{L}\\p{N}_])",
                options: [.caseInsensitive]
            ) else {
                return []
            }
            let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
            return expression.matches(in: text, range: fullRange).map { ($0.range, snippet.value) }
        }

        let ordered = candidates
            .sorted {
                if $0.0.location != $1.0.location { return $0.0.location < $1.0.location }
                return $0.0.length > $1.0.length
            }
            .reduce(into: [(NSRange, String)]()) { selected, candidate in
                guard let last = selected.last else {
                    selected.append(candidate)
                    return
                }
                let lastEnd = last.0.location + last.0.length
                guard candidate.0.location >= lastEnd else { return }
                selected.append(candidate)
            }

        guard !ordered.isEmpty else { return text }
        var expanded = text
        for (range, value) in ordered.reversed() {
            guard let swiftRange = Range(range, in: expanded) else { continue }
            expanded.replaceSubrange(swiftRange, with: value)
        }
        return expanded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    private nonisolated static func isUsable(_ snippet: Snippet) -> Bool {
        !snippet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !snippet.value.isEmpty
    }
}
