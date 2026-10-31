extends RefCounted
class_name ShootingResult
## The outcome of one squad's shooting: which models fired, why the others
## could not, and every hit roll. Hits and misses only; no wounds yet.


## One model's part in the shooting.
class ModelResult:
    var model_name: String
    var weapon: WeaponProfile
    var eligibility: int
    ## Distance to the nearest target model, in board units (INF if none).
    var distance := INF
    var rolls: Array[int] = []
    var hits := 0

    func is_eligible() -> bool:
        return eligibility == ShootingRules.Eligibility.ELIGIBLE


var firing_squad: SquadState
var target_squad: SquadState
var model_results: Array[ModelResult] = []


func get_eligible_count() -> int:
    return model_results.filter(func(r): return r.is_eligible()).size()


func get_ineligible_count() -> int:
    return model_results.size() - get_eligible_count()


func get_total_attacks() -> int:
    var total := 0
    for r in model_results:
        total += r.rolls.size()
    return total


func get_hits() -> int:
    var total := 0
    for r in model_results:
        total += r.hits
    return total


func get_misses() -> int:
    return get_total_attacks() - get_hits()
