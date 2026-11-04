extends RefCounted
class_name ChargeRules
## Charge rules as pure functions: who may charge, declaration checks, the
## charge distance, each model's fixed target model, and success. Nothing here
## changes state or rolls dice.
##
## Rules (approved by the project lead):
##   - Only a squad that MoraleRules.may_charge allows (Steady, not
##     restricted), that is not committed to an engagement this round and not
##     in base contact with an enemy now, may declare a charge.
##   - It declares exactly one enemy squad as its target, before rolling.
##   - A declaration is refused, without spending the activation, unless some
##     living charging model is within the maximum possible charge (M + 6) of
##     some living target model, edge to edge in a straight line.
##   - Charge distance is the squad's Movement plus one D6, rolled once per
##     squad: the most each model may move, independent of (and not
##     consuming) its Movement-phase allowance. Difficult terrain doubles.
##   - Each model heads for the living target model nearest it (edge to edge)
##     when the charge begins, fixed for the charge; ties go to the lower
##     model_id.
##   - The charge succeeds if at least one charging model ends in base contact
##     with a model of the target squad. Charging models may never come into
##     base contact with any other enemy squad.

enum Result { OK, NO_SQUAD, NO_TARGET, WRONG_PHASE, NOT_ACTIVATED, OWN_SQUAD, MORALE_RESTRICTED, ALREADY_ENGAGED,
    TARGET_UNAVAILABLE, OUT_OF_RANGE }

## Highest possible charge roll.
const MAX_ROLL := 6


## True if `squad` is currently in base contact with any enemy among `squads`
## (an ongoing engagement).
static func in_enemy_contact(squad: SquadState, squads: Array) -> bool:
    for other in squads:
        if EngagementRules.squads_in_contact(squad, other):
            return true
    return false


## Whether `squad` may declare any charge this phase: morale allows it, it is
## not already engaged this round or in contact now, and an enemy squad exists.
static func can_declare_any(squad: SquadState, squads: Array, tracker: EngagementTracker) -> bool:
    if squad == null or squad.get_leader() == null or not MoraleRules.may_charge(squad):
        return false
    if tracker and tracker.is_committed(squad.squad_id):
        return false
    if in_enemy_contact(squad, squads):
        return false
    for other in squads:
        if other.get_player() != squad.get_player() and other.get_model_count() > 0:
            return true
    return false


## Checks a declaration of `charger` against `target`. Changes nothing.
static func validate(charger: SquadState, target: SquadState, phase: TurnManager.Phase, charger_is_activated: bool,
        squads: Array, tracker: EngagementTracker) -> Result:
    if charger == null:
        return Result.NO_SQUAD
    if target == null:
        return Result.NO_TARGET
    if phase != TurnManager.Phase.CHARGE:
        return Result.WRONG_PHASE
    if not charger_is_activated:
        return Result.NOT_ACTIVATED
    if target.get_player() == charger.get_player():
        return Result.OWN_SQUAD
    if not MoraleRules.may_charge(charger):
        return Result.MORALE_RESTRICTED
    if (tracker and tracker.is_committed(charger.squad_id)) or in_enemy_contact(charger, squads):
        return Result.ALREADY_ENGAGED
    var engagement := tracker.engagement_of(target.squad_id) if tracker else null
    if target.get_model_count() == 0 or (engagement and engagement.resolved):
        return Result.TARGET_UNAVAILABLE
    if closest_edge_distance(charger, target) > max_charge_distance(charger) + MovementRules.EPSILON:
        return Result.OUT_OF_RANGE
    return Result.OK


## Enemy squads `charger` could legally declare a charge against now: exactly
## those validate() accepts (as the activated squad in the Charge phase).
static func valid_targets(charger: SquadState, squads: Array, tracker: EngagementTracker) -> Array[SquadState]:
    var targets: Array[SquadState] = []
    for other in squads:
        if other.get_player() != charger.get_player() \
                and validate(charger, other, TurnManager.Phase.CHARGE, true, squads, tracker) == Result.OK:
            targets.append(other)
    return targets


## Most a charge by `squad` could ever reach: Movement + 6.
static func max_charge_distance(squad: SquadState) -> float:
    return MovementRules.allowance_for(squad.data) + MAX_ROLL


## Distance each model may move for a charge with `roll` on the D6.
static func charge_distance(squad: SquadState, roll: int) -> float:
    return MovementRules.allowance_for(squad.data) + roll


## Smallest straight-line edge-to-edge distance between any living model of
## `a` and any living model of `b` (INF if either has none).
static func closest_edge_distance(a: SquadState, b: SquadState) -> float:
    var best := INF
    for ma in a.get_living_models():
        for mb in b.get_living_models():
            best = minf(best, _edge_distance(ma, mb))
    return best


## The living model of `target` nearest `model`, edge to edge; ties go to the
## lower model_id. Null if the target has none.
static func nearest_target_model(model: ModelState, target: SquadState) -> ModelState:
    var best: ModelState = null
    var best_distance := INF
    for candidate in target.get_living_models():
        var d := _edge_distance(model, candidate)
        if d < best_distance:
            best = candidate
            best_distance = d
    return best


## True if some living model of `charger` is in base contact with a living
## model of `target`.
static func succeeded(charger: SquadState, target: SquadState) -> bool:
    return EngagementRules.squads_in_contact(charger, target)


static func _edge_distance(a: ModelState, b: ModelState) -> float:
    return a.position.distance_to(b.position) - a.get_base_radius() - b.get_base_radius()
