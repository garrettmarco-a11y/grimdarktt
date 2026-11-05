extends RefCounted
class_name ShootingRules
## Shooting rules as pure functions: order validation, per-model eligibility,
## range and hit resolution. No scene, input or drawing dependencies.
##
## Rules (initial, per the project lead's brief):
##   - Only the activated squad may shoot, only in the Shooting phase, and only
##     at an enemy squad that is not currently participating in an active
##     engagement (EngagementRules: connected enemy base contact now, not
##     round-long commitment). Friendly squads are never targets. There is no
##     firing into a melee, no hit redirection and no random target.
##   - Each model is checked on its own; an ineligible model adds no shots but
##     never stops the rest of the squad firing.
##   - Range is measured from the firing model to the nearest target model; a
##     target exactly at the weapon's range is in range.
##   - The model needs line of sight to a target model that is in range.
##   - A target squad may only be chosen if at least one living firing model
##     has line of sight to at least one of its living models.
##   - Each attack rolls one D6 and hits on a roll >= CombatModifiers.hit_target:
##     the firer's Quality, one higher while Shaken, one higher again if the
##     target squad is in heavy cover.
##   - Morale may forbid shooting this turn (MoraleRules.may_attack).
##   - Target legality is never judged without the engagement context: every
##     validation takes the authoritative BattleState and finds engagements
##     among all of its squads, so no squad can be left out. A missing battle,
##     or a firing or target squad that is not that battle's squad of the same
##     id, is an invariant failure: refused as NO_ENGAGEMENT_CONTEXT, with an
##     error, rather than judged without the engagement check.

enum OrderResult { OK, NO_SQUAD, NO_TARGET, WRONG_PHASE, NOT_ACTIVATED, OWN_SQUAD, ALLOCATION_PENDING, MORALE_RESTRICTED, NO_VISIBLE_TARGET,
    ENGAGED_TARGET, NO_ENGAGEMENT_CONTEXT }

## Tolerance for range comparisons, in board units.
const EPSILON := 0.001


## Checks an order by `firing` to shoot `target`. `battle` (required) is the
## authoritative battlefield: current engagements are found among all of its
## squads (EngagementRules), and `firing` and `target` must be its squads, or
## the order is refused with NO_ENGAGEMENT_CONTEXT.
static func validate_order(firing: SquadState, target: SquadState, phase: TurnManager.Phase,
        firing_is_activated: bool, battle: BattleState) -> OrderResult:
    if firing == null:
        return OrderResult.NO_SQUAD
    if target == null:
        return OrderResult.NO_TARGET
    if phase != TurnManager.Phase.SHOOTING:
        return OrderResult.WRONG_PHASE
    if not firing_is_activated:
        return OrderResult.NOT_ACTIVATED
    if not MoraleRules.may_attack(firing):
        return OrderResult.MORALE_RESTRICTED
    if target.get_player() == firing.get_player():
        return OrderResult.OWN_SQUAD
    if battle == null:
        push_error("ShootingRules.validate_order: no battlefield to judge engagements by")
        return OrderResult.NO_ENGAGEMENT_CONTEXT
    for squad in [firing, target]:
        if battle.get_squad(squad.squad_id) != squad:
            push_error("ShootingRules.validate_order: %s is not a squad of this battlefield" % squad.squad_id)
            return OrderResult.NO_ENGAGEMENT_CONTEXT
    if EngagementRules.is_in_active_engagement(target, battle.get_squads()):
        return OrderResult.ENGAGED_TARGET
    return OrderResult.OK


## True if any living firing model can see any living target model.
static func has_visible_target(firing: SquadState, target: SquadState, los: LineOfSight) -> bool:
    var shooters: Array[Vector2] = []
    for model in firing.get_living_models():
        shooters.append(firing.get_model_position(model))
    if shooters.is_empty():
        shooters.append(firing.board_position)
    for shooter in shooters:
        for point in target_points(target):
            if los.has_line_of_sight(shooter, point):
                return true
    return false


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
        targets: Array[Vector2], los: LineOfSight) -> CombatResult.ModelResult:
    var result := CombatResult.ModelResult.new()
    result.model_name = model_name
    result.weapon = weapon
    for point in targets:
        result.distance = minf(result.distance, position.distance_to(point))
    if not is_ranged_weapon(weapon):
        result.eligibility = CombatResult.Eligibility.NO_RANGED_WEAPON
        return result
    var any_in_range := false
    for point in targets:
        if in_range(weapon, position.distance_to(point)):
            any_in_range = true
            if los.has_line_of_sight(position, point):
                result.eligibility = CombatResult.Eligibility.ELIGIBLE
                return result
    result.eligibility = CombatResult.Eligibility.NO_LINE_OF_SIGHT if any_in_range else CombatResult.Eligibility.OUT_OF_RANGE
    return result


## Rolls `attacks` D6, each hitting on `quality` or more. Returns the rolls.
static func roll_attacks(attacks: int, dice: DiceRoller) -> Array[int]:
    var rolls: Array[int] = []
    for i in attacks:
        rolls.append(dice.roll_d6())
    return rolls


static func is_hit(roll: int, quality: int) -> bool:
    return roll >= quality


## Resolves hits from every living model in `firing` at `target`, using the
## target's squad-wide cover from `terrain` (none if null). Wounds and saves are
## rolled separately by DamageRules.
static func resolve(firing: SquadState, target: SquadState, los: LineOfSight,
        dice: DiceRoller, terrain: TerrainMap = null) -> CombatResult:
    var result := CombatResult.new()
    result.attacker_squad = firing
    result.target_squad = target
    result.target_cover = TerrainRules.squad_cover(target, terrain)
    result.target_armor_save = TerrainRules.majority_armor_save(target)
    result.hit_target = CombatModifiers.hit_target(firing, result.target_cover)
    var targets := target_points(target)
    var quality := result.hit_target
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
