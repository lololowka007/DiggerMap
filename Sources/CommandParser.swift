import Foundation

enum CommandParser {
    private static let units: [String: Double] = [
        "ноль": 0, "один": 1, "одна": 1, "одно": 1, "два": 2, "две": 2,
        "три": 3, "четыре": 4, "пять": 5, "шесть": 6, "семь": 7,
        "восемь": 8, "девять": 9, "десять": 10, "одиннадцать": 11,
        "двенадцать": 12, "тринадцать": 13, "четырнадцать": 14,
        "пятнадцать": 15, "шестнадцать": 16, "семнадцать": 17,
        "восемнадцать": 18, "девятнадцать": 19,
        "двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50,
        "шестьдесят": 60, "семьдесят": 70, "восемьдесят": 80,
        "девяносто": 90, "сто": 100,
        "одного": 1, "двух": 2, "трех": 3, "четырех": 4,
        "пяти": 5, "шести": 6, "семи": 7, "восьми": 8, "девяти": 9,
        "десяти": 10, "полтора": 1.5, "полторы": 1.5
    ]

    static func parse(_ raw: String, stepLength: Double = 0.75) -> [RouteCommand] {
        let text = raw.lowercased().replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        if text == "стоп" || text.contains("остановил") || text.contains("остановился") || text.contains("не иду") {
            return [.walking(false)]
        }
        let parts = text.components(separatedBy: " потом ")
        if parts.count > 1 { return parts.flatMap { parse($0, stepLength: stepLength) } }
        if let marker = text.range(of: "^(точка|метка|заметка)\\s*:?[\\s]*", options: .regularExpression) {
            let label = String(text[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return [.note(label.isEmpty ? "Точка" : label.capitalized)]
        }
        if text.contains("развилка") { return [.note("Развилка")] }
        if text.contains("дверь") { return [.note("Дверь")] }
        if text.contains("выход") { return [.note("Выход")] }
        if text.contains("лестница") { return [.note("Лестница")] }
        if text.contains("ширин") {
            if let width = number(before: "метр", in: text) { return [.width(width)] }
        }
        if text.contains("подъем") || text.contains("вверх") || text.contains("этаж выше") { return [.level(1)] }
        if text.contains("спуск") || text.contains("вниз") || text.contains("этаж ниже") { return [.level(-1)] }

        var commands: [RouteCommand] = []
        let left = text.contains("налево") || text.contains("влево") || text.contains("левее") || text.contains("в левую")
        let right = text.contains("направо") || text.contains("вправо") || text.contains("правее") || text.contains("в правую")
        if left != right {
            let angle = number(before: "градус", in: text)
                ?? (text.contains("чуть") || text.contains("слегка") ? 12 : 90)
            if angle > 0 && angle <= 180 { commands.append(.turn(left ? -angle : angle)) }
        }
        if let meters = number(before: "метр", in: text) {
            commands.append(.move(meters))
        } else if let steps = number(before: "шаг", in: text) {
            commands.append(.move(steps * stepLength))
        } else if text.contains("полметра") {
            commands.append(.move(0.5))
        } else if text.contains("иду") || text.contains("идем") || text.contains("двигаюсь") || text.contains("двигаемся") {
            commands.append(.walking(true))
        } else if text.contains("прямо") {
            commands.append(.walking(true))
        }
        return commands
    }

    private static func number(before unit: String, in text: String) -> Double? {
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "," && $0 != "." }).map(String.init)
        guard let unitIndex = words.firstIndex(where: { $0.hasPrefix(unit) }), unitIndex > 0 else { return nil }
        let window = words[max(0, unitIndex - 3)..<unitIndex]
        if let numeric = window.reversed().compactMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }).first {
            return numeric
        }
        var sum = 0.0
        var found = false
        for word in window {
            if let value = units[word] {
                sum += value
                found = true
            }
        }
        return found ? sum : nil
    }
}
