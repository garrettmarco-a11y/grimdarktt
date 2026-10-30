extends RefCounted
class_name SquadState
## A squad's current condition on the battlefield (runtime only, never saved).
##
## SquadData describes what the squad is; SquadState describes where it is now.
## Statistics are read from `data` and never copied here. This is the
## authoritative source for the squad's position; visual tokens follow it.

signal position_changed(state: SquadState)

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

var _squad_id: StringName
var _data: SquadData


func _init(squad_data: SquadData, start_position := Vector2.ZERO) -> void:
    _data = squad_data
    _squad_id = squad_data.squad_id if squad_data else &""
    board_position = start_position


func get_player() -> int:
    return _data.player if _data else 0
