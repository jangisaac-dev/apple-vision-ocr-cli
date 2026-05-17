import Foundation

public enum LanguageParser {
    public static func parse(_ rawValue: String) throws -> [String] {
        let languages = rawValue
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard !languages.isEmpty, languages.allSatisfy({ !$0.isEmpty }) else {
            throw AppleVisionOCRError.invalidUsage("language list cannot be empty")
        }

        return languages
    }
}
