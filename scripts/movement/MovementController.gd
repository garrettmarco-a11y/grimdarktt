extends Node
class_name MovementController
## Applies squad movement orders: validates them with MovementRules, updates the
## authoritative SquadState, and resets every squad's movement when a new turn
## starts. Has no input or drawing code; it never touches visual nodes.

signal move_ordered(state: SquadState, from: Vector2, to: Vector2)
signal move_rejected(state: SquadState, destination: Vector2, result: MovementRules.Result)

## Battlefield size in board units, used to reject off-board destinations.
var board_size := Vector2.ZERO
## When set, only the currently activated squad may be ordered to move.
var activation: ActivationController
## Battlefield terrain for difficult and impassable movement; none if null.
var terrain: TerrainMap
## How the models moved on the last accepted order.
var last_plan: SquadMover.Plan

var _battle: BattleState
var _turn_manager: TurnManager


func bind(battle: BattleState, turn_manager: TurnManager, board_units: Vector2) -> void:
    _battle = battle
    _turn_manager = turn_manager
    board_size = board_units
    battle.squad_added.connect(_begin_squad_turn)
    turn_manager.turn_started.connect(_on_turn_started)
    for state in battle.get_squads():
        _begin_squad_turn(state)


## Orders `state`'s leader to move to `destination` (board units); the
## followers make for their formation slots. Returns the result; only an OK
## order changes the squad's state. The resolved plan is kept in last_plan.
func order_move(state: SquadState, destination: Vector2) -> MovementRules.Result:
    var activated := activation == null or activation.is_active_squad(state)
    var result := MovementRules.validate(state, destination, _turn_manager.current_phase, board_size, activated,
        terrain, _battle.get_squads())
    if result != MovementRules.Result.OK:
        move_rejected.emit(state, destination, result)
        return result
    var from := state.board_position
    last_plan = SquadMover.plan_move(state, destination, _battle.get_squads(), terrain, board_size)
    var leader := state.get_leader()
    var leader_left := state.movement_allowance - leader.movement_used - last_plan.cost_of(leader)
    state.apply_model_moves(last_plan.moves, leader_left <= MovementRules.EPSILON)
    _check_layout()
    move_ordered.emit(state, from, state.board_position)
    return result


## Allowance the leader would spend on a move to `destination`, for feedback.
func order_cost(state: SquadState, destination: Vector2) -> float:
    return MovementRules.leader_cost(state, destination, terrain)


## Movement must never leave bases overlapping; report it if it ever does.
func _check_layout() -> void:
    for pair in ModelPlacement.find_overlaps(_battle.get_squads()):
        push_error("MovementController: %s overlaps %s" % [ModelPlacement.describe(pair[0], pair[1]),
            ModelPlacement.describe(pair[2], pair[3])])


func _on_turn_started(_turn: int) -> void:
    for state in _battle.get_squads():
        _begin_squad_turn(state)


func _begin_squad_turn(state: SquadState) -> void:
    state.begin_turn_movement(MovementRules.allowance_for(state.data) * MoraleRules.movement_factor(state))
