extends RefCounted
class_name MoraleRules
## Morale rules as pure functions: tests, the shared movement and hit modifiers,
## what a squad may still do this turn, and fall-back geometry. Dice come from
## an injected DiceRoller; nothing here changes game state.
##
## Rules (approved by the project lead):
##   - A morale test rolls 2D6 and passes on a total equal to or below the
##     leader's Leadership, -1 if the squad is below half its starting strength.
##   - Shaken: movement allowance halved; -1 to hit, applied as a Quality
##     target one higher (no automatic hit on a 6, so 7+ cannot hit).
##   - A Broken squad, or one that consolidated or took a rally test this turn,
##     may not shoot or initiate an assault.
##   - Fall-back moves the leader anchor its full normal Movement straight
##     towards the nearest battlefield edge; ties go west, east, north, south.
##     Crossing the edge takes the squad off the battlefield.

enum Edge { WEST, EAST, NORTH, SOUTH }

## Tolerance for distance comparisons, in board units.
const EPSILON := 0.001


static func roll_2d6(dice: DiceRoller) -> Array[int]:
    return [dice.roll_d6(), dice.roll_d6()]


static func base_leadership(state: SquadState) -> int:
    var profile := state.get_leader_profile()
    return profile.leadership if profile else 0


static func effective_leadership(state: SquadState) -> int:
    return base_leadership(state) - (1 if state.is_below_half_strength() else 0)


static func passes(total: int, leadership: int) -> bool:
    return total <= leadership


## Multiplier applied to a squad's normal Movement for this turn's allowance.
static func movement_factor(state: SquadState) -> float:
    return 0.5 if state.morale_status == SquadState.MoraleStatus.SHAKEN else 1.0


## The D6 roll a model of `state` needs to hit: its Quality, one higher while
## Shaken. Used by both shooting and assault.
static func hit_target(state: SquadState) -> int:
    var quality := state.data.profile.quality if state.data and state.data.profile else 0
    return quality + (1 if state.morale_status == SquadState.MoraleStatus.SHAKEN else 0)


## Whether morale lets `state` shoot or initiate an assault this turn.
static func may_attack(state: SquadState) -> bool:
    return state.morale_status != SquadState.MoraleStatus.BROKEN and not state.morale_restricted_this_turn


static func edge_distance(anchor: Vector2, board_size: Vector2, edge: Edge) -> float:
    match edge:
        Edge.WEST:
            return anchor.x
        Edge.EAST:
            return board_size.x - anchor.x
        Edge.NORTH:
            return anchor.y
    return board_size.y - anchor.y


## The battlefield edge nearest `anchor`; ties go west, east, north, south.
static func nearest_edge(anchor: Vector2, board_size: Vector2) -> Edge:
    var best := Edge.WEST
    for edge in [Edge.EAST, Edge.NORTH, Edge.SOUTH]:
        if edge_distance(anchor, board_size, edge) < edge_distance(anchor, board_size, best) - EPSILON:
            best = edge
    return best


static func edge_direction(edge: Edge) -> Vector2:
    match edge:
        Edge.WEST:
            return Vector2.LEFT
        Edge.EAST:
            return Vector2.RIGHT
        Edge.NORTH:
            return Vector2.UP
    return Vector2.DOWN


## Where the anchor ends after falling back `distance` towards the nearest
## edge. May lie beyond the battlefield.
static func fallback_destination(anchor: Vector2, board_size: Vector2, distance: float) -> Vector2:
    return anchor + edge_direction(nearest_edge(anchor, board_size)) * distance


## True if `point` lies beyond the battlefield (on the edge is still on it).
static func is_off_board(point: Vector2, board_size: Vector2) -> bool:
    return point.x < -EPSILON or point.y < -EPSILON \
        or point.x > board_size.x + EPSILON or point.y > board_size.y + EPSILON


static func edge_name(edge: Edge) -> String:
    return ["west", "east", "north", "south"][edge]
