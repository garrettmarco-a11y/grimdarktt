@tool
extends Node2D
class_name SquadToken
## Placeholder marker for one squad on the battlefield.
##
## Representation only: it draws the SquadState it is given and keeps no
## battlefield data of its own. SquadLayer sets `target_position` from the
## state and pushes the `selected` display flag; the token decides neither.
## The token glides toward its target; that animation is never read back as
## the squad's position.

const PLAYER_COLORS := {
    1: Color(0.30, 0.55, 0.95),
    2: Color(0.90, 0.30, 0.25),
}
const NEUTRAL_COLOR := Color(0.6, 0.6, 0.6)
const SELECTION_COLOR := Color(1.0, 0.86, 0.35)
const ACTIVE_COLOR := Color(1.0, 1.0, 1.0)
const SHAKEN_COLOR := Color(1.0, 0.65, 0.15)
const BROKEN_COLOR := Color(0.95, 0.15, 0.15)
## Radius of a model dot, in pixels; also its click radius.
const MODEL_RADIUS := 5.0

## Activation display states, pushed in by SquadLayer.
enum ActivationDisplay { READY, ACTIVE, SPENT }

## Glide speed toward `target_position`, in pixels per second.
@export var move_speed := 240.0
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
## Display flag only; activation itself is owned by ActivationController.
var activation_display := ActivationDisplay.READY:
    set(value):
        activation_display = value
        queue_redraw()
## Display copy of the squad's SquadState.MoraleStatus, pushed in by SquadLayer.
var morale_status := SquadState.MoraleStatus.STEADY:
    set(value):
        morale_status = value
        queue_redraw()
## Pixel offsets of the squad's models from the marker, set by SquadLayer.
var model_offsets: Array[Vector2] = []:
    set(value):
        model_offsets = value
        queue_redraw()
## Pixel position of the squad's authoritative board position.
var target_position := Vector2.ZERO:
    set(value):
        target_position = value
        set_process(position != target_position)


func _ready() -> void:
    set_process(position != target_position)


func _process(delta: float) -> void:
    advance(delta)


## Moves the marker up to `delta` seconds' worth toward its target.
func advance(delta: float) -> void:
    position = position.move_toward(target_position, move_speed * delta)
    if position == target_position:
        set_process(false)


## Jumps straight to the target, e.g. when first placed.
func snap_to_target() -> void:
    position = target_position
    set_process(false)


func is_moving() -> bool:
    return position != target_position


func get_squad_id() -> StringName:
    return state.squad_id if state else &""


func get_player() -> int:
    return state.get_player() if state else 0


## True if `local_point` (in this token's local pixels) is on the marker or
## one of its model dots.
func contains_local_point(local_point: Vector2) -> bool:
    if local_point.length() <= radius:
        return true
    for offset in model_offsets:
        if local_point.distance_to(offset) <= MODEL_RADIUS + 2.0:
            return true
    return false


func _draw() -> void:
    var color: Color = PLAYER_COLORS.get(get_player(), NEUTRAL_COLOR)
    if activation_display == ActivationDisplay.SPENT:
        color = color.lerp(NEUTRAL_COLOR, 0.6).darkened(0.35)
    if activation_display == ActivationDisplay.ACTIVE:
        draw_circle(Vector2.ZERO, radius + 11.0, ACTIVE_COLOR, false, 2.0)
    if selected:
        draw_circle(Vector2.ZERO, radius + 6.0, SELECTION_COLOR, false, 3.0)
    for offset in model_offsets:
        draw_circle(offset, MODEL_RADIUS, color.darkened(0.45))
        draw_circle(offset, MODEL_RADIUS - 1.5, color)
    draw_circle(Vector2.ZERO, radius, color.darkened(0.45))
    draw_circle(Vector2.ZERO, radius - 4.0, color)
    if morale_status == SquadState.MoraleStatus.SHAKEN:
        draw_arc(Vector2.ZERO, radius + 2.0, PI, TAU, 16, SHAKEN_COLOR, 4.0)
    elif morale_status == SquadState.MoraleStatus.BROKEN:
        var r := radius * 0.6
        draw_line(Vector2(-r, -r), Vector2(r, r), BROKEN_COLOR, 4.0)
        draw_line(Vector2(-r, r), Vector2(r, -r), BROKEN_COLOR, 4.0)
