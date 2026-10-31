extends RefCounted
class_name DamageRules
## Wound, armor-save and casualty-allocation rules as pure functions. Dice come
## from an injected DiceRoller; nothing here changes game state.
##
## Rules (approved by the project lead):
##   - Each hit rolls one D6 to wound, against Strength vs Toughness:
##     S >= 2T: 2+, S > T: 3+, S == T: 4+, S < T: 5+, S <= T/2: 6+.
##   - Each wound allows one D6 armor save against the target's armor_save plus
##     the weapon's AP. A target number worse than 6+ cannot be saved.
##   - A natural 1 always fails, both to wound and to save.
##   - Each unsaved wound is one point of damage. The defender allocates each
##     one to any living model in the target squad.

enum AllocationResult { OK, NO_PENDING_WOUNDS, UNKNOWN_MODEL, MODEL_REMOVED }

## A save target above this cannot succeed.
const BEST_POSSIBLE_TARGET := 6


static func wound_target(strength: int, toughness: int) -> int:
    if strength >= 2 * toughness:
        return 2
    if strength > toughness:
        return 3
    if strength == toughness:
        return 4
    if 2 * strength <= toughness:
        return 6
    return 5


static func is_wound(roll: int, target: int) -> bool:
    return roll != 1 and roll >= target


## Save target number after AP, or 0 if the target has no armor save.
static func save_target(armor_save: int, armor_piercing: int) -> int:
    if armor_save <= 0:
        return 0
    return armor_save + maxi(armor_piercing, 0)


static func can_be_saved(target: int) -> bool:
    return target > 0 and target <= BEST_POSSIBLE_TARGET


static func is_saved(roll: int, target: int) -> bool:
    return can_be_saved(target) and roll != 1 and roll >= target


## For each firing model: rolls a wound for every hit, then a save for every
## wound, using the target squad's Toughness and armor save. Fills the
## per-model wound and save fields; allocation happens separately.
static func resolve_wounds_and_saves(result: ShootingResult, dice: DiceRoller) -> void:
    var profile := result.target_squad.data.profile if result.target_squad.data else null
    var toughness := profile.toughness if profile else 0
    var armor_save := profile.armor_save if profile else 0
    for model in result.model_results:
        if model.hits == 0:
            continue
        model.wound_target = wound_target(model.weapon.strength, toughness)
        model.save_target = save_target(armor_save, model.weapon.armor_piercing)
        for i in model.hits:
            var roll := dice.roll_d6()
            model.wound_rolls.append(roll)
            if is_wound(roll, model.wound_target):
                model.wounds += 1
        if not can_be_saved(model.save_target):
            continue
        for i in model.wounds:
            var save := dice.roll_d6()
            model.save_rolls.append(save)
            if is_saved(save, model.save_target):
                model.saves += 1


## Whether one unsaved wound may be allocated to `model_id` in `target`.
static func validate_allocation(target: SquadState, model_id: int, wounds_left: int) -> AllocationResult:
    if wounds_left <= 0:
        return AllocationResult.NO_PENDING_WOUNDS
    var model := target.get_model(model_id) if target else null
    if model == null:
        return AllocationResult.UNKNOWN_MODEL
    if model.removed:
        return AllocationResult.MODEL_REMOVED
    return AllocationResult.OK
