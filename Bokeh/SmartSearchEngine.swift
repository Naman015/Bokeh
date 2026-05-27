import Foundation
import NaturalLanguage

// MARK: - Smart Search Engine
// Demonstrating On-Device NLP for Swift Student Challenge - 100% Private
// Uses Apple's NaturalLanguage framework to extract meaningful keywords from
// natural language queries like "Where are my keys?" or "Did I clear a cup?"

struct SmartSearchEngine {

    /// Extracts noun keywords from a natural language query.
    /// For example: "Where are my keys?" → ["keys"]
    ///              "Did I put a cup in the drawer?" → ["cup", "drawer"]
    static func extractKeywords(from query: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = query

        var keywords: [String] = []

        tagger.enumerateTags(
            in: query.startIndex..<query.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            // Extract nouns (the meaningful objects/places in a query)
            if let tag = tag, tag == .noun {
                let word = String(query[range]).lowercased()
                // Filter out very short words and common filler nouns
                if word.count >= 2 && !Self.fillerNouns.contains(word) {
                    keywords.append(word)
                }
            }
            return true
        }

        return keywords
    }

    /// Common filler nouns that don't help search (e.g., "thing", "stuff")
    private static let fillerNouns: Set<String> = [
        "thing", "things", "stuff", "item", "items", "something", "anything",
        "place", "spot", "way", "one", "ones"
    ]

    /// Performs smart search on a collection of items.
    /// Falls back to simple string matching if no keywords are extracted.
    static func search<T>(
        items: [T],
        query: String,
        labelKeyPath: KeyPath<T, String>,
        locationKeyPath: KeyPath<T, String?>
    ) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        let keywords = extractKeywords(from: trimmed)

        // If NLP extracted keywords, use smart matching
        if !keywords.isEmpty {
            return items.filter { item in
                let label = item[keyPath: labelKeyPath].lowercased()
                let location = item[keyPath: locationKeyPath]?.lowercased() ?? ""

                // Match if ANY keyword is found in label OR location
                return keywords.contains { keyword in
                    label.contains(keyword) || location.contains(keyword)
                }
            }
        }

        // Fallback: simple string contains match
        let lowercased = trimmed.lowercased()
        return items.filter { item in
            let label = item[keyPath: labelKeyPath].lowercased()
            let location = item[keyPath: locationKeyPath]?.lowercased() ?? ""
            return label.contains(lowercased) || location.contains(lowercased)
        }
    }
}
