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


## Orders `state` to move to `destination` (board units). Returns the result;
## only an OK order changes the squad's state.
func order_move(state: SquadState, destination: Vector2) -> MovementRules.Result:
    var activated := activation == null or activation.is_active_squad(state)
    var result := MovementRules.validate(state, destination, _turn_manager.current_phase, board_size, activated)
    if result != MovementRules.Result.OK:
        move_rejected.emit(state, destination, result)
        return result
    var from := state.board_position
    state.apply_move(destination, MovementRules.exhausts_allowance(state, destination))
    move_ordered.emit(state, from, destination)
    return result


func _on_turn_started(_turn: int) -> void:
    for state in _battle.get_squads():
        _begin_squad_turn(state)


func _begin_squad_turn(state: SquadState) -> void:
    state.begin_turn_movement(MovementRules.allowance_for(state.data))
