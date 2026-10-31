extends RefCounted
class_name ShootingRules
## Shooting rules as pure functions: order validation, per-model eligibility,
## range and hit resolution. No scene, input or drawing dependencies.
##
## Rules (initial, per the project lead's brief):
##   - Only the activated squad may shoot, only in the Shooting phase, and only
##     at an enemy squad.
##   - Each model is checked on its own; an ineligible model adds no shots but
##     never stops the rest of the squad firing.
##   - Range is measured from the firing model to the nearest target model; a
##     target exactly at the weapon's range is in range.
##   - The model needs line of sight to a target model that is in range.
##   - Each attack rolls one D6 and hits on a roll >= the firer's Quality.

enum OrderResult { OK, NO_SQUAD, NO_TARGET, WRONG_PHASE, NOT_ACTIVATED, OWN_SQUAD, ALLOCATION_PENDING }
enum Eligibility { ELIGIBLE, NO_RANGED_WEAPON, OUT_OF_RANGE, NO_LINE_OF_SIGHT }

## Tolerance for range comparisons, in board units.
const EPSILON := 0.001


static func validate_order(firing: SquadState, target: SquadState, phase: TurnManager.Phase,
        firing_is_activated: bool) -> OrderResult:
    if firing == null:
        return OrderResult.NO_SQUAD
    if target == null:
        return OrderResult.NO_TARGET
    if phase != TurnManager.Phase.SHOOTING:
        return OrderResult.WRONG_PHASE
    if not firing_is_activated:
        return OrderResult.NOT_ACTIVATED
    if target.get_player() == firing.get_player():
        return OrderResult.OWN_SQUAD
    return OrderResult.OK


static func is_ranged_weapon(weapon: WeaponProfile) -> bool:
    return weapon != null and weapon.range > 0.0 and weapon.attacks > 0


static func in_range(weapon: WeaponProfile, distance: float) -> bool:
    return distance <= weapon.range + EPSILON


## Board positions of the target's living models, or its anchor if it lists none.
static func target_points(target: SquadState) -> Array[Vector2]:
    var points: Array[Vector2] = []
    for model in target.get_living_models():
        points.append(target.get_model_position(model))
    if points.is_empty():
        points.append(target.board_position)
    return points


## Checks whether a model with `weapon` at `position` can fire at `targets`.
## Fills the result's eligibility and nearest-target distance; rolls nothing.
static func evaluate_model(model_name: String, weapon: WeaponProfile, position: Vector2,
        targets: Array[Vector2], los: LineOfSight) -> ShootingResult.ModelResult:
    var result := ShootingResult.ModelResult.new()
    result.model_name = model_name
    result.weapon = weapon
    for point in targets:
        result.distance = minf(result.distance, position.distance_to(point))
    if not is_ranged_weapon(weapon):
        result.eligibility = Eligibility.NO_RANGED_WEAPON
        return result
    var any_in_range := false
    for point in targets:
        if in_range(weapon, position.distance_to(point)):
            any_in_range = true
            if los.has_line_of_sight(position, point):
                result.eligibility = Eligibility.ELIGIBLE
                return result
    result.eligibility = Eligibility.NO_LINE_OF_SIGHT if any_in_range else Eligibility.OUT_OF_RANGE
    return result


## Rolls `attacks` D6, each hitting on `quality` or more. Returns the rolls.
static func roll_attacks(attacks: int, dice: DiceRoller) -> Array[int]:
    var rolls: Array[int] = []
    for i in attacks:
        rolls.append(dice.roll_d6())
    return rolls


static func is_hit(roll: int, quality: int) -> bool:
    return roll >= quality


## Resolves hits from every living model in `firing` at `target`. Wounds and
## saves are rolled separately by DamageRules.
static func resolve(firing: SquadState, target: SquadState, los: LineOfSight,
        dice: DiceRoller) -> ShootingResult:
    var result := ShootingResult.new()
    result.firing_squad = firing
    result.target_squad = target
    var targets := target_points(target)
    var quality := firing.data.profile.quality if firing.data.profile else 0
    for model in firing.get_living_models():
        var model_result := evaluate_model(model.get_model_name(), model.get_weapon(),
            firing.get_model_position(model), targets, los)
        if model_result.is_eligible():
            model_result.rolls = roll_attacks(model.get_weapon().attacks, dice)
            for roll in model_result.rolls:
                if is_hit(roll, quality):
                    model_result.hits += 1
        result.model_results.append(model_result)
    return result
