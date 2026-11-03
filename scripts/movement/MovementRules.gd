extends RefCounted
class_name MovementRules
## Movement rules as pure functions: allowance, distance and order validation.
## No scene, animation or input dependencies, so it is testable on its own.
##
## Rules (agreed with the project lead):
##   - Orders are only accepted in the Movement phase, and only for the squad
##     that is currently activated.
##   - A squad's allowance for the turn is its leader's M characteristic. Until
##     squads have model rosters, the squad's single profile stands in for the
##     leader's.
##   - Distance is the straight-line distance in continuous board units,
##     measured from the squad's position at the start of the turn.
##   - A destination is valid if it is on the battlefield and within the
##     allowance of the turn-start position.
##   - Once a squad has moved its full allowance its movement is complete.
##   - Morale can reduce the allowance (MoraleRules.movement_factor, applied by
##     MovementController); forced fall-back moves bypass these rules,
##     including terrain.
##   - Terrain: each living model moves in a straight line from its turn-start
##     position to its destination (the squad keeps its formation). Distance in
##     difficult terrain costs double; the squad's cost is its most restricted
##     model's, checked against the (possibly halved) allowance. No model may
##     pass through a terrain piece's impassable_area.

enum Result { OK, NO_SQUAD, WRONG_PHASE, NOT_ACTIVATED, MOVEMENT_COMPLETE, OFF_BOARD, OUT_OF_RANGE, IMPASSABLE }

## Tolerance for float comparisons, in board units.
const EPSILON := 0.001


static func allowance_for(squad: SquadData) -> float:
    if squad == null or squad.profile == null:
        return 0.0
    return maxf(squad.profile.movement, 0.0)


static func distance(from: Vector2, to: Vector2) -> float:
    return from.distance_to(to)


## Checks a move order for `state` to `destination` (board units) during
## `phase`, on a board of `board_size` units. `squad_is_activated` says whether
## `state` is the currently activated squad. Changes nothing.
static func validate(state: SquadState, destination: Vector2, phase: TurnManager.Phase,
        board_size: Vector2, squad_is_activated := true, terrain: TerrainMap = null) -> Result:
    if state == null:
        return Result.NO_SQUAD
    if phase != TurnManager.Phase.MOVEMENT:
        return Result.WRONG_PHASE
    if not squad_is_activated:
        return Result.NOT_ACTIVATED
    if state.movement_complete:
        return Result.MOVEMENT_COMPLETE
    if destination.x < 0.0 or destination.y < 0.0 \
            or destination.x > board_size.x or destination.y > board_size.y:
        return Result.OFF_BOARD
    if terrain:
        for path in model_paths(state, destination):
            if terrain.crosses_impassable(path[0], path[1]):
                return Result.IMPASSABLE
    if movement_cost(state, destination, terrain) > state.movement_allowance + EPSILON:
        return Result.OUT_OF_RANGE
    return Result.OK


## [turn-start position, destination] for each living model if the squad moves
## its anchor to `destination`; just the anchor's if it lists no models.
static func model_paths(state: SquadState, destination: Vector2) -> Array:
    var paths := []
    var anchor := state.board_position
    for model in state.get_living_models():
        paths.append([model.turn_start_position, destination + model.position - anchor])
    if paths.is_empty():
        paths.append([state.turn_start_position, destination])
    return paths


## Allowance a move to `destination` uses: the highest cost among the living
## models' paths from their turn-start positions (difficult terrain doubled).
static func movement_cost(state: SquadState, destination: Vector2, terrain: TerrainMap = null) -> float:
    var cost := 0.0
    for path in model_paths(state, destination):
        var model_cost: float = terrain.movement_cost(path[0], path[1]) if terrain else distance(path[0], path[1])
        cost = maxf(cost, model_cost)
    return cost


## True if moving `state` to `destination` uses its full allowance this turn.
static func exhausts_allowance(state: SquadState, destination: Vector2, terrain: TerrainMap = null) -> bool:
    return movement_cost(state, destination, terrain) >= state.movement_allowance - EPSILON
