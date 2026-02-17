import Foundation

struct TextNormalizationOptions: OptionSet {
    let rawValue: Int

    static let stripFeaturingSuffix = TextNormalizationOptions(rawValue: 1 << 0)
    static let stripParentheticalText = TextNormalizationOptions(rawValue: 1 << 1)
    static let alphanumericsOnly = TextNormalizationOptions(rawValue: 1 << 2)
    static let collapseWhitespace = TextNormalizationOptions(rawValue: 1 << 3)

    static let defaultMatching: TextNormalizationOptions = [.alphanumericsOnly, .collapseWhitespace]
}

enum CreditsTextNormalizer {
    static func normalize(_ value: String, options: TextNormalizationOptions = .defaultMatching) -> String {
        var cleaned = value.lowercased()

        if options.contains(.stripFeaturingSuffix),
           let range = cleaned.range(of: #"\b(feat\.?|featuring)\b.*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }

        if options.contains(.stripParentheticalText) {
            cleaned = cleaned.replacingOccurrences(
                of: #"\([^\)]*\)"#,
                with: " ",
                options: .regularExpression
            )
        }

        if options.contains(.alphanumericsOnly) {
            let scalarView = cleaned.unicodeScalars.map { scalar -> Character in
                if CharacterSet.alphanumerics.contains(scalar) {
                    return Character(scalar)
                }
                return " "
            }
            cleaned = String(scalarView)
        }

        if options.contains(.collapseWhitespace) {
            cleaned = cleaned
                .split(separator: " ")
                .map(String.init)
                .joined(separator: " ")
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CreditsTextSimilarity {
    static func jaccardSimilarity(_ lhs: String, _ rhs: String, containsMatchScore: Double = 0.87) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return 0
        }

        if lhs == rhs {
            return 1
        }

        if lhs.contains(rhs) || rhs.contains(lhs) {
            return containsMatchScore
        }

        let leftTokens = Set(lhs.split(separator: " ").map(String.init))
        let rightTokens = Set(rhs.split(separator: " ").map(String.init))

        guard !leftTokens.isEmpty, !rightTokens.isEmpty else {
            return 0
        }

        let intersection = leftTokens.intersection(rightTokens).count
        let union = leftTokens.union(rightTokens).count
        guard union > 0 else {
            return 0
        }

        return Double(intersection) / Double(union)
    }
}
