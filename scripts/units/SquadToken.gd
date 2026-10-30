@tool
extends Node2D
class_name SquadToken
## Placeholder marker for one squad on the battlefield.
##
## Representation only: it draws the SquadState it is given and keeps no
## battlefield data of its own. SquadLayer sets its pixel position from the
## state and pushes the `selected` display flag; the token decides neither.

const PLAYER_COLORS := {
    1: Color(0.30, 0.55, 0.95),
    2: Color(0.90, 0.30, 0.25),
}
const NEUTRAL_COLOR := Color(0.6, 0.6, 0.6)
const SELECTION_COLOR := Color(1.0, 0.86, 0.35)

## Marker radius in pixels; also the click radius.
@export var radius := 18.0:
    set(value):
        radius = value
        queue_redraw()

var state: SquadState:
    set(value):
        state = value
        queue_redraw()
## Display flag only; the selection itself is owned by SelectionManager.
var selected := false:
    set(value):
        selected = value
        queue_redraw()


func get_squad_id() -> StringName:
    return state.squad_id if state else &""


func get_player() -> int:
    return state.get_player() if state else 0


## True if `local_point` (in this token's local pixels) is on the marker.
func contains_local_point(local_point: Vector2) -> bool:
    return local_point.length() <= radius


func _draw() -> void:
    var color: Color = PLAYER_COLORS.get(get_player(), NEUTRAL_COLOR)
    if selected:
        draw_circle(Vector2.ZERO, radius + 6.0, SELECTION_COLOR, false, 3.0)
    draw_circle(Vector2.ZERO, radius, color.darkened(0.45))
    draw_circle(Vector2.ZERO, radius - 4.0, color)
