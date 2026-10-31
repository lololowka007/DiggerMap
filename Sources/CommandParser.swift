import Foundation

enum CommandParser {
    private static let numbers: [String: Double] = [
        "ноль":0,"один":1,"одна":1,"одно":1,"одного":1,"два":2,"две":2,"двух":2,"пару":2,"пара":2,
        "три":3,"трех":3,"четыре":4,"четырех":4,"пять":5,"пяти":5,"шесть":6,"шести":6,
        "семь":7,"семи":7,"восемь":8,"восьми":8,"девять":9,"девяти":9,"десять":10,"десяти":10,
        "одиннадцать":11,"двенадцать":12,"тринадцать":13,"четырнадцать":14,"пятнадцать":15,
        "шестнадцать":16,"семнадцать":17,"восемнадцать":18,"девятнадцать":19,"двадцать":20,
        "тридцать":30,"сорок":40,"пятьдесят":50,"шестьдесят":60,"семьдесят":70,
        "восемьдесят":80,"девяносто":90,"сто":100,"полтора":1.5,"полторы":1.5
    ]

    static func parse(_ raw: String, stepLength: Double = 0.75, smallTurn: Double = 12) -> [RouteCommand] {
        let text = normalize(raw)
        guard !text.isEmpty else { return [] }
        let sequential = text.components(separatedBy: " потом ")
        if sequential.count > 1 {
            return sequential.flatMap { parse($0, stepLength: stepLength, smallTurn: smallTurn) }
        }
        if text == "стоп" || text == "стой" || text.contains("останов") || text.contains("не иду") {
            return [.walking(false)]
        }
        if let range = text.range(of: "^(точка|метка|заметка)\\s*:?[\\s]*", options: .regularExpression) {
            let value = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return [.marker(draft(value.isEmpty ? "Точка" : value, original: raw))]
        }
        if text.contains("стрелк") || text.contains("надпись") || text.contains("написано") ||
            text.contains("таблич") || text.contains("обозначен") || text.contains("фото") || text.contains("опасн") {
            return [.marker(draft(text, original: raw))]
        }
        let moving = ["иду","идем","прошел","прошли","двига","возвращ","отступ","шагнул"].contains { text.contains($0) }
        let scene = ["передо мной","перед нами","вижу","есть проход","проходы","развилка","ответвлен"].contains { text.contains($0) }
        if scene || (!moving && text.contains("проход")) {
            return [.marker(draft(text, original: raw, observation: true))]
        }
        if text.contains("тупик") && !moving && !["развор","развер","разворач"].contains(where: { text.contains($0) }) {
            return [.marker(draft(text, original: raw, observation: isLeft(text) || isRight(text)))]
        }
        if text.contains("ширин"), let width = number(before: "метр", in: text) { return [.width(width)] }

        var result: [RouteCommand] = []
        if text.contains("тупик") { result.append(.marker(draft(text, original: raw))) }
        let uTurn = ["развор","развер","разворач"].contains { text.contains($0) } ||
            (text.contains("поворач") && (text.contains("назад") || text.contains("обратно"))) ||
            (text.contains("180") && text.contains("градус"))
        let distance = number(before: "метр", in: text) ??
            number(before: "шаг", in: text).map { $0 * stepLength } ??
            (text.contains("полметра") ? 0.5 : nil)
        if uTurn {
            result.append(.turn(180))
            if let distance { result.append(.move(distance)) }
            return result
        }
        if text.contains("назад") || text.contains("обратно") || text.contains("отступ") {
            if let distance { return result + [.backtrack(distance)] }
            return result + [.turn(180)]
        }
        if ["поднимаюсь","поднялся","поднялись","этаж выше","перешел выше"].contains(where: { text.contains($0) }) || text == "вверх" || text == "подъем" {
            return result + [.level(max(1, min(10, Int(number(before: "этаж", in: text) ?? 1))))]
        }
        if ["спускаюсь","спустился","спустились","этаж ниже","перешел ниже"].contains(where: { text.contains($0) }) || text == "вниз" || text == "спуск" {
            return result + [.level(-max(1, min(10, Int(number(before: "этаж", in: text) ?? 1))))]
        }
        let left = isLeft(text), right = isRight(text)
        if left != right {
            let angle = number(before: "градус", in: text) ?? (text.contains("чуть") || text.contains("слегка") ? smallTurn : 90)
            if angle > 0 && angle <= 180 { result.append(.turn(left ? -angle : angle)) }
        }
        if let distance { result.append(.move(distance)) }
        else if moving || text.contains("прямо") { result.append(.walking(true)) }
        if result.isEmpty && ["дверь","лестниц","выход","здесь","вижу"].contains(where: { text.contains($0) }) {
            result.append(.marker(draft(text, original: raw)))
        }
        return result
    }

    private static func draft(_ text: String, original: String, observation: Bool = false) -> MarkerDraft {
        let passages = parsePassages(text)
        var kind: MarkerKind = observation ? .junction : .note
        if text.contains("тупик") && !observation { kind = .deadEnd }
        else if text.contains("стрелк") { kind = .arrow }
        else if text.contains("надпись") || text.contains("написано") || text.contains("таблич") || text.contains("обозначен") { kind = .sign }
        else if text.contains("фото") { kind = .photo }
        else if text.contains("опасн") || text.contains("обвал") { kind = .danger }
        else if text.contains("лестниц") { kind = .stairs }
        else if text.contains("развор") || text.contains("развер") { kind = .uTurn }
        else if !passages.isEmpty { kind = .junction }
        let title = kind == .note ? String(text.prefix(45)).capitalized : kind.title
        return MarkerDraft(kind: kind, title: title, detail: original, passages: passages)
    }

    static func parsePassages(_ raw: String) -> [Passage] {
        let text = normalize(raw)
        let clauses = text.replacingOccurrences(of: " и ", with: ",").replacingOccurrences(of: " а ", with: ",")
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
        var result: [Passage] = []
        for clause in clauses {
            let elevation = ["выше","вверх","подъем","наверх"].contains(where: { clause.contains($0) }) ? 1 :
                ["ниже","вниз","спуск"].contains(where: { clause.contains($0) }) ? -1 : 0
            let amount = number(before: "градус", in: clause) ?? 90
            let ending = clause.contains("тупик") ? " · тупик" : ""
            if isLeft(clause) { result.append(Passage(angle: -amount, elevation: elevation, label: "Налево" + ending)) }
            if isRight(clause) { result.append(Passage(angle: amount, elevation: elevation, label: "Направо" + ending)) }
            if clause.contains("прямо") || clause.contains("вперед") { result.append(Passage(angle: 0, elevation: elevation, label: "Прямо")) }
            if clause.contains("сзади") || clause.contains("назад") { result.append(Passage(angle: 180, elevation: elevation, label: "Назад")) }
            if result.isEmpty && elevation != 0 { result.append(Passage(angle: 0, elevation: elevation, label: elevation > 0 ? "Выше" : "Ниже")) }
        }
        return Array(result.prefix(8))
    }

    private static func normalize(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "на лево", with: "налево").replacingOccurrences(of: "на право", with: "направо")
            .replacingOccurrences(of: "°", with: " градусов ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func isLeft(_ text: String) -> Bool {
        ["налево","влево","левее","слева","левый","левую"].contains { text.contains($0) }
    }
    private static func isRight(_ text: String) -> Bool {
        ["направо","вправо","правее","справа","правый","правую"].contains { text.contains($0) }
    }
    private static func number(before unit: String, in text: String) -> Double? {
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "," && $0 != "." }).map(String.init)
        guard let index = words.firstIndex(where: { $0.hasPrefix(unit) || (unit == "метр" && ["м","м."].contains($0)) }), index > 0 else { return nil }
        var window: [String] = []
        for word in words[max(0, index - 6)..<index].reversed() {
            if Double(word.replacingOccurrences(of: ",", with: ".")) != nil || numbers[word] != nil {
                window.insert(word, at: 0)
            } else if !window.isEmpty && ["или","до"].contains(word) {
                window.insert(word, at: 0)
            } else if !window.isEmpty { break }
        }
        let values = window.compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) ?? numbers[$0] }
        guard !values.isEmpty else { return nil }
        if window.contains("или") || window.contains("до") { return values.reduce(0, +) / Double(values.count) }
        if let digit = window.reversed().compactMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }).first { return digit }
        return values.reduce(0, +)
    }
}
