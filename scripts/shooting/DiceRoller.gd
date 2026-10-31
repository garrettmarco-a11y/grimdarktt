extends RefCounted
class_name DiceRoller
## Source of dice rolls. Rules take a DiceRoller rather than calling the global
## random functions, so tests can supply fixed rolls.

var _rng := RandomNumberGenerator.new()


## A negative `seed_value` seeds randomly; any other value gives a repeatable sequence.
func _init(seed_value := -1) -> void:
    if seed_value < 0:
        _rng.randomize()
    else:
        _rng.seed = seed_value


func roll_d6() -> int:
    return _rng.randi_range(1, 6)
