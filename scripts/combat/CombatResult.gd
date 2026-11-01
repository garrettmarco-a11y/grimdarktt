extends RefCounted
class_name CombatResult
## The outcome of one squad's attack, ranged (shooting) or melee (assault):
## which models attacked, why the others could not, every hit, wound and save
## roll, and where the defender allocated the unsaved wounds.

enum AttackType { RANGED, MELEE }
## Why a model could or could not attack.
enum Eligibility { ELIGIBLE, NO_RANGED_WEAPON, OUT_OF_RANGE, NO_LINE_OF_SIGHT, NO_MELEE_WEAPON, NOT_ENGAGED }


## One model's part in the attack.
class ModelResult:
    var model_name: String
    var weapon: WeaponProfile
    var eligibility: int
    ## Distance to the nearest target model, in board units (INF if none).
    var distance := INF
    var rolls: Array[int] = []
    var hits := 0
    ## Wound roll needed (2-6), set once the model has hits.
    var wound_target := 0
    var wound_rolls: Array[int] = []
    var wounds := 0
    ## Save target after AP, or 0 if the target has no save.
    var save_target := 0
    var save_rolls: Array[int] = []
    var saves := 0

    func is_eligible() -> bool:
        return eligibility == CombatResult.Eligibility.ELIGIBLE

    func get_unsaved() -> int:
        return wounds - saves


## One unsaved wound placed by the defender.
class Allocation:
    var model_id: int
    var model_name: String
    var removed: bool


var attack_type := AttackType.RANGED
var attacker_squad: SquadState
var target_squad: SquadState
var model_results: Array[ModelResult] = []
var allocations: Array[Allocation] = []
## Unsaved wounds left unallocated because the target squad was destroyed.
var wasted_wounds := 0
var models_remaining := 0
var target_destroyed := false


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


func get_wounds() -> int:
    var total := 0
    for r in model_results:
        total += r.wounds
    return total


func get_saves() -> int:
    var total := 0
    for r in model_results:
        total += r.saves
    return total


func get_unsaved_wounds() -> int:
    return get_wounds() - get_saves()


## Names of the models removed by this shooting, in the order they fell.
func get_casualties() -> PackedStringArray:
    var names := PackedStringArray()
    for a in allocations:
        if a.removed:
            names.append(a.model_name)
    return names
