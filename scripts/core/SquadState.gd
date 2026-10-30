extends RefCounted
class_name SquadState
## A squad's current condition on the battlefield (runtime only, never saved).
##
## SquadData describes what the squad is; SquadState describes where it is now.
## Statistics are read from `data` and never copied here. This is the
## authoritative source for the squad's position and movement tracking; visual
## tokens follow it. Movement rules live in MovementRules / MovementController.

signal position_changed(state: SquadState)
## Emitted when movement tracking (turn start, allowance or completion) changes.
signal movement_changed(state: SquadState)

## Stable identifier, taken from the squad's data at creation.
var squad_id: StringName:
    get:
        return _squad_id
    set(_value):
        push_error("SquadState.squad_id is read-only")
## The squad's persistent configuration.
var data: SquadData:
    get:
        return _data
    set(_value):
        push_error("SquadState.data is read-only")
## Current position in board distance units (continuous, not snapped).
var board_position := Vector2.ZERO:
    set(value):
        if value == board_position:
            return
        board_position = value
        position_changed.emit(self)

## Where the squad stood when the current turn's movement began.
var turn_start_position := Vector2.ZERO
## Maximum distance from turn_start_position this turn, in board units.
var movement_allowance := 0.0
## True once the squad may not move again this turn.
var movement_complete := false
## Straight-line distance from turn_start_position to the current position.
var distance_moved: float:
    get:
        return turn_start_position.distance_to(board_position)

var _squad_id: StringName
var _data: SquadData


func _init(squad_data: SquadData, start_position := Vector2.ZERO) -> void:
    _data = squad_data
    _squad_id = squad_data.squad_id if squad_data else &""
    board_position = start_position
    turn_start_position = start_position


## Starts a new turn's movement from the current position with `allowance`.
func begin_turn_movement(allowance: float) -> void:
    turn_start_position = board_position
    movement_allowance = allowance
    movement_complete = false
    movement_changed.emit(self)


## Moves to `destination` and records whether movement is now complete. The
## caller (MovementController) is responsible for validating the order.
func apply_move(destination: Vector2, complete: bool) -> void:
    board_position = destination
    movement_complete = complete
    movement_changed.emit(self)


func get_remaining_movement() -> float:
    return maxf(movement_allowance - distance_moved, 0.0)


func get_player() -> int:
    return _data.player if _data else 0
