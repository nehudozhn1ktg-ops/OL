extends RefCounted
class_name Dice

## Кубик и монета. В тестах подставляются заранее заданные значения,
## поэтому проверки детерминированные, а в игре бросает настоящий генератор.

var rng := RandomNumberGenerator.new()
var forced_rolls: Array[int] = []
var forced_coins: Array[String] = []


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## D4 — по правилам атаки и защиты. min_value задаёт нижнюю границу
## (всплеск эссенции поднимает её до 3).
func d4(min_value: int = 1) -> int:
	if not forced_rolls.is_empty():
		return forced_rolls.pop_front()
	return rng.randi_range(min_value, 4)


## Монета при проигрыше в защите: "white" — выжил и ранен, "black" — погиб.
func coin() -> String:
	if not forced_coins.is_empty():
		return forced_coins.pop_front()
	return "white" if rng.randi_range(0, 1) == 1 else "black"


## Удобно для тестов: задать последовательность.
func force(rolls: Array[int], coins: Array[String] = []) -> void:
	for value in rolls:
		forced_rolls.append(value)
	for value in coins:
		forced_coins.append(value)
