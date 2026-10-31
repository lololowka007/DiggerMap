import Foundation

enum CommandParser {
    private static let numbers: [String: Int] = [
        "один": 1, "два": 2, "три": 3, "четыре": 4, "пять": 5,
        "шесть": 6, "семь": 7, "восемь": 8, "девять": 9, "десять": 10,
        "одиннадцать": 11, "двенадцать": 12, "пятнадцать": 15,
        "двадцать": 20, "тридцать": 30, "сорок": 40, "сорок пять": 45,
        "пятьдесят": 50, "сто": 100
    ]

    static func parse(_ raw: String) -> RouteCommand {
        let text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unknown }
        if text.hasPrefix("точка") || text.hasPrefix("метка") || text.hasPrefix("заметка") {
            let value = text.replacingOccurrences(of: "^(точка|метка|заметка)\\s*:?[\\s]*", with: "", options: .regularExpression)
            return .note(value.isEmpty ? "Точка" : value)
        }
        if text.contains("вверх") || text.contains("подъём") || text.contains("подъем") { return .level(1) }
        if text.contains("вниз") || text.contains("спуск") { return .level(-1) }
        if text.contains("налево") || text.contains("влево") { return .turn(text.contains("45") || text.contains("сорок пять") ? -45 : -90) }
        if text.contains("направо") || text.contains("вправо") { return .turn(text.contains("45") || text.contains("сорок пять") ? 45 : 90) }
        if text.contains("шаг") || text.contains("прямо") {
            if let match = text.range(of: "[0-9]+", options: .regularExpression),
               let value = Int(text[match]) { return .move(value) }
            for (word, value) in numbers.sorted(by: { $0.key.count > $1.key.count }) where text.contains(word) {
                return .move(value)
            }
        }
        return .unknown
    }
}
