@tool
extends Node2D
class_name SquadToken
## Placeholder marker for one squad on the battlefield.
##
## Representation only: identity and statistics come from `data`, and the
## marker can be redrawn or replaced without touching them. Selection state is
## pushed in by SquadLayer; the token never decides selection itself.

const PLAYER_COLORS := {
    1: Color(0.30, 0.55, 0.95),
    2: Color(0.90, 0.30, 0.25),
}
const NEUTRAL_COLOR := Color(0.6, 0.6, 0.6)
const SELECTION_COLOR := Color(1.0, 0.86, 0.35)

@export var data: SquadData:
    set(value):
        data = value
        queue_redraw()
## Position on the battlefield in board distance units (continuous, not snapped).
@export var board_position := Vector2.ZERO
## Marker radius in pixels; also the click radius.
@export var radius := 18.0:
    set(value):
        radius = value
        queue_redraw()

var selected := false:
    set(value):
        selected = value
        queue_redraw()


func get_squad_id() -> StringName:
    return data.squad_id if data else &""


func get_player() -> int:
    return data.player if data else 0


## True if `local_point` (in this token's local pixels) is on the marker.
func contains_local_point(local_point: Vector2) -> bool:
    return local_point.length() <= radius


func _draw() -> void:
    var color: Color = PLAYER_COLORS.get(get_player(), NEUTRAL_COLOR)
    if selected:
        draw_circle(Vector2.ZERO, radius + 6.0, SELECTION_COLOR, false, 3.0)
    draw_circle(Vector2.ZERO, radius, color.darkened(0.45))
    draw_circle(Vector2.ZERO, radius - 4.0, color)
