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
