extends RefCounted
class_name AssaultRules
## Assault (melee) rules as pure functions: order validation, per-model
## engagement and hit resolution. Wounds, saves and casualties reuse
## DamageRules and the CasualtyAllocator. No scene, input or drawing code.
##
## Rules (approved by the project lead):
##   - Only the activated squad may assault, only in the Assault phase, and
##     only an enemy squad.
##   - A model may attack if it has a melee weapon and is within
##     ENGAGEMENT_DISTANCE of at least one living model of the target squad,
##     measured centre to centre between models. Others add no attacks but never
##     stop the rest of the squad.
##   - Each attack rolls one D6 and hits on a roll >= the attacker's Quality
##     (the established hit rule; no automatic natural-1 miss), one higher while
##     Shaken (MoraleRules.hit_target).
##   - Morale may forbid initiating an assault (MoraleRules.may_attack). Being
##     attacked is unaffected: there is no defensive fighting step yet.
##   - Line of sight does not apply to melee.

enum OrderResult { OK, NO_SQUAD, NO_TARGET, WRONG_PHASE, NOT_ACTIVATED, OWN_SQUAD, ALLOCATION_PENDING, MORALE_RESTRICTED }

## Maximum centre-to-centre distance between an attacking model and a target
## model for the attacker to be engaged, in board units (inclusive).
const ENGAGEMENT_DISTANCE := 2.0
## Tolerance for distance comparisons, in board units.
const EPSILON := 0.001


static func validate_order(attacker: SquadState, target: SquadState, phase: TurnManager.Phase,
        attacker_is_activated: bool) -> OrderResult:
    if attacker == null:
        return OrderResult.NO_SQUAD
    if target == null:
        return OrderResult.NO_TARGET
    if phase != TurnManager.Phase.ASSAULT:
        return OrderResult.WRONG_PHASE
    if not attacker_is_activated:
        return OrderResult.NOT_ACTIVATED
    if not MoraleRules.may_attack(attacker):
        return OrderResult.MORALE_RESTRICTED
    if target.get_player() == attacker.get_player():
        return OrderResult.OWN_SQUAD
    return OrderResult.OK


static func is_melee_weapon(weapon: WeaponProfile) -> bool:
    return weapon != null and weapon.attacks > 0


static func is_engaged(distance: float) -> bool:
    return distance <= ENGAGEMENT_DISTANCE + EPSILON


## Checks whether a model with `weapon` at `position` can attack any of
## `targets` in melee. Fills eligibility and nearest-target distance.
static func evaluate_model(model_name: String, weapon: WeaponProfile, position: Vector2,
        targets: Array[Vector2]) -> CombatResult.ModelResult:
    var result := CombatResult.ModelResult.new()
    result.model_name = model_name
    result.weapon = weapon
    for point in targets:
        result.distance = minf(result.distance, position.distance_to(point))
    if not is_melee_weapon(weapon):
        result.eligibility = CombatResult.Eligibility.NO_MELEE_WEAPON
    elif not is_engaged(result.distance):
        result.eligibility = CombatResult.Eligibility.NOT_ENGAGED
    else:
        result.eligibility = CombatResult.Eligibility.ELIGIBLE
    return result


## Resolves melee hits from every living model in `attacker` at `target`.
## Wounds and saves are rolled separately by DamageRules.
static func resolve(attacker: SquadState, target: SquadState, dice: DiceRoller) -> CombatResult:
    var result := CombatResult.new()
    result.attack_type = CombatResult.AttackType.MELEE
    result.attacker_squad = attacker
    result.target_squad = target
    var targets := ShootingRules.target_points(target)
    var quality := MoraleRules.hit_target(attacker)
    for model in attacker.get_living_models():
        var model_result := evaluate_model(model.get_model_name(), model.get_melee_weapon(),
            attacker.get_model_position(model), targets)
        if model_result.is_eligible():
            model_result.rolls = ShootingRules.roll_attacks(model_result.weapon.attacks, dice)
            for roll in model_result.rolls:
                if ShootingRules.is_hit(roll, quality):
                    model_result.hits += 1
        result.model_results.append(model_result)
    return result
