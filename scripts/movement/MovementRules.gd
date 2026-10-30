extends RefCounted
class_name MovementRules
## Movement rules as pure functions: allowance, distance and order validation.
## No scene, animation or input dependencies, so it is testable on its own.
##
## Rules (agreed with the project lead):
##   - Orders are only accepted in the Movement phase.
##   - A squad's allowance for the turn is its leader's M characteristic. Until
##     squads have model rosters, the squad's single profile stands in for the
##     leader's.
##   - Distance is the straight-line distance in continuous board units,
##     measured from the squad's position at the start of the turn.
##   - A destination is valid if it is on the battlefield and within the
##     allowance of the turn-start position.
##   - Once a squad has moved its full allowance its movement is complete.

enum Result { OK, NO_SQUAD, WRONG_PHASE, MOVEMENT_COMPLETE, OFF_BOARD, OUT_OF_RANGE }

## Tolerance for float comparisons, in board units.
const EPSILON := 0.001


static func allowance_for(squad: SquadData) -> float:
    if squad == null or squad.profile == null:
        return 0.0
    return maxf(squad.profile.movement, 0.0)


static func distance(from: Vector2, to: Vector2) -> float:
    return from.distance_to(to)


## Checks a move order for `state` to `destination` (board units) during
## `phase`, on a board of `board_size` units. Changes nothing.
static func validate(state: SquadState, destination: Vector2, phase: TurnManager.Phase,
        board_size: Vector2) -> Result:
    if state == null:
        return Result.NO_SQUAD
    if phase != TurnManager.Phase.MOVEMENT:
        return Result.WRONG_PHASE
    if state.movement_complete:
        return Result.MOVEMENT_COMPLETE
    if destination.x < 0.0 or destination.y < 0.0 \
            or destination.x > board_size.x or destination.y > board_size.y:
        return Result.OFF_BOARD
    if distance(state.turn_start_position, destination) > state.movement_allowance + EPSILON:
        return Result.OUT_OF_RANGE
    return Result.OK


## True if moving `state` to `destination` uses its full allowance this turn.
static func exhausts_allowance(state: SquadState, destination: Vector2) -> bool:
    return distance(state.turn_start_position, destination) >= state.movement_allowance - EPSILON
