import Foundation

var route = RouteState()
precondition(route.apply(CommandParser.parse("я прошёл около четырёх метров"),
                         source: "я прошёл около четырёх метров"))
precondition(abs(route.totalMeters - 4) < 0.001)
precondition(route.points.count == 2)

precondition(route.apply(CommandParser.parse("на 12 градусов налево"),
                         source: "на 12 градусов налево"))
precondition(abs(route.heading - 348) < 0.001)

precondition(route.apply(CommandParser.parse("прямо 12 шагов"),
                         source: "прямо 12 шагов"))
precondition(abs(route.totalMeters - 13) < 0.001)

var corridor = RouteState()
precondition(corridor.apply(CommandParser.parse("я прошёл по коридору четыре метра"),
                            source: "я прошёл по коридору четыре метра"))
precondition(abs(corridor.totalMeters - 4) < 0.001)
precondition(abs(corridor.corridorWidth - 2) < 0.001)

print("Voice route parsing: OK")

let walking = CommandParser.parse("я иду прямо")
precondition(walking.contains { if case .walking(true) = $0 { return true }; return false })
var left100 = RouteState()
precondition(left100.apply(CommandParser.parse("я иду налево, сто метров."), source: "test"))
precondition(abs(left100.totalMeters - 100) < 0.001)
precondition(abs((left100.points.last?.x ?? 0) + 100) < 0.001)
precondition(abs(left100.points.last?.y ?? 0) < 0.001)

var segmenter = UtteranceSegmenter()
for _ in 0..<10 { precondition(segmenter.consume(Array(repeating: 0, count: 1600)).phrase == nil) }
var phrases = 0
for _ in 0..<12 {
    if segmenter.consume(Array(repeating: 0.1, count: 1600)).phrase != nil { phrases += 1 }
}
for _ in 0..<20 {
    if segmenter.consume(Array(repeating: 0, count: 1600)).phrase != nil { phrases += 1 }
}
precondition(phrases == 1, "One spoken phrase must produce exactly one command")

if CommandLine.arguments.count > 1 {
    let heard = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    var actual = RouteState()
    precondition(actual.apply(CommandParser.parse(heard), source: heard), "Real audio was not understood")
    precondition(abs(actual.totalMeters - 100) < 0.001, "Real audio distance must be 100m")
    precondition(abs((actual.points.last?.x ?? 0) + 100) < 0.001, "Real audio must go left")
    print("AUDIO → TEXT → MAP: OK")
}
