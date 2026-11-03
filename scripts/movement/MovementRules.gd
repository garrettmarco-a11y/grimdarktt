extends RefCounted
class_name MovementRules
## Movement rules as pure functions: allowance, distance and order validation.
## No scene, animation or input dependencies, so it is testable on its own.
##
## Rules (agreed with the project lead):
##   - Orders are only accepted in the Movement phase, and only for the squad
##     that is currently activated. The squad's leader receives the order;
##     SquadMover resolves how every model moves.
##   - Every model's allowance for the turn is the leader's M characteristic.
##     Until models carry their own profiles, the squad's single profile
##     stands in for the leader's. Morale can reduce it
##     (MoraleRules.movement_factor, applied by MovementController).
##   - Movement costs the distance a model actually travels, summed over every
##     order (leg) this turn; distance through difficult terrain costs double,
##     measured along the model's centre path. Each model has its own budget.
##   - An order is valid if the leader's whole base stays on the battlefield,
##     its base never overlaps impassable terrain or another squad's model on
##     the straight path to the destination, and the path's cost fits the
##     leader's remaining allowance. The leader's own followers are not
##     checked here: they move at the same time (see SquadMover).
##   - Once the leader has no allowance left the squad's movement is complete.
##   - Forced fall-back moves bypass these rules (see MoraleController).

enum Result { OK, NO_SQUAD, WRONG_PHASE, NOT_ACTIVATED, MOVEMENT_COMPLETE, OFF_BOARD, OUT_OF_RANGE, IMPASSABLE, BLOCKED_BY_MODEL }

## Tolerance for float comparisons, in board units.
const EPSILON := 0.001


static func allowance_for(squad: SquadData) -> float:
    if squad == null or squad.profile == null:
        return 0.0
    return maxf(squad.profile.movement, 0.0)


static func distance(from: Vector2, to: Vector2) -> float:
    return from.distance_to(to)


## Checks a move order for `state`'s leader to `destination` (board units)
## during `phase`, on a board of `board_size` units. `squad_is_activated` says
## whether `state` is the currently activated squad; `others` are the squads
## whose models may block the leader. Changes nothing.
static func validate(state: SquadState, destination: Vector2, phase: TurnManager.Phase,
        board_size: Vector2, squad_is_activated := true, terrain: TerrainMap = null, others: Array = []) -> Result:
    if state == null:
        return Result.NO_SQUAD
    if phase != TurnManager.Phase.MOVEMENT:
        return Result.WRONG_PHASE
    if not squad_is_activated:
        return Result.NOT_ACTIVATED
    if state.movement_complete:
        return Result.MOVEMENT_COMPLETE
    var leader := state.get_leader()
    if leader == null:
        return Result.NO_SQUAD
    var radius := leader.get_base_radius()
    if not ModelPlacement.base_on_board(destination, radius, board_size):
        return Result.OFF_BOARD
    if terrain and terrain.base_crosses_impassable(leader.position, destination, radius):
        return Result.IMPASSABLE
    for other in others:
        if other == state:
            continue
        for model in other.get_living_models():
            if ModelPlacement.path_hits_base(leader.position, destination, radius, model.position, model.get_base_radius()):
                return Result.BLOCKED_BY_MODEL
    if leader_cost(state, destination, terrain) > state.get_remaining_movement() + EPSILON:
        return Result.OUT_OF_RANGE
    return Result.OK


## Allowance the leader would spend going straight from where it stands to
## `destination` (difficult terrain doubled).
static func leader_cost(state: SquadState, destination: Vector2, terrain: TerrainMap = null) -> float:
    var leader := state.get_leader()
    if leader == null:
        return 0.0
    return terrain.movement_cost(leader.position, destination) if terrain else distance(leader.position, destination)
