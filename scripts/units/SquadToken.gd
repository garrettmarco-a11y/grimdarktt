@tool
extends Node2D
class_name SquadToken
## Placeholder view of one squad on the battlefield: one disc per living
## model at its true base size, the leader ringed, with the squad's selection,
## activation and morale markers drawn around the leader.
##
## Representation only: it draws the SquadState it is given and keeps no
## battlefield data of its own. SquadLayer sets `target_position` (the
## leader's position) and each model's offset from it, both from the
## authoritative state, and pushes the display flags. The token and each model
## glide toward their targets; that animation is never read back as anyone's
## position.

const PLAYER_COLORS := {
    1: Color(0.30, 0.55, 0.95),
    2: Color(0.90, 0.30, 0.25),
}
const NEUTRAL_COLOR := Color(0.6, 0.6, 0.6)
const SELECTION_COLOR := Color(1.0, 0.86, 0.35)
const ACTIVE_COLOR := Color(1.0, 1.0, 1.0)
## Ring marking a squad held by its engagement this round.
const ENGAGED_COLOR := Color(0.95, 0.35, 0.2)
const SHAKEN_COLOR := Color(1.0, 0.65, 0.15)
const BROKEN_COLOR := Color(0.95, 0.15, 0.15)
## Extra click margin around each base, in pixels.
const CLICK_MARGIN := 2.0

## Activation display states, pushed in by SquadLayer.
enum ActivationDisplay { READY, ACTIVE, SPENT, ENGAGED }

## Glide speed toward `target_position`, in pixels per second.
@export var move_speed := 240.0
## Radius of the leader's base in pixels, set by SquadLayer; the squad
## markers are drawn around it.
var radius := 10.0:
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
## Pixel offsets of the squad's living models from the leader (the first is
## the leader), set by SquadLayer. Each drawn model glides to its offset.
var model_offsets: Array[Vector2] = []:
    set(value):
        if value.size() != _shown_offsets.size():
            _shown_offsets = value.duplicate()
        model_offsets = value
        set_process(is_moving())
        queue_redraw()
## Base radius of each living model in pixels, in the same order.
var model_radii: Array[float] = []:
    set(value):
        model_radii = value
        queue_redraw()
## Pixel position of the squad's authoritative board position.
var target_position := Vector2.ZERO:
    set(value):
        target_position = value
        set_process(is_moving())

## Offsets currently drawn, gliding toward model_offsets.
var _shown_offsets: Array[Vector2] = []


func _ready() -> void:
    set_process(is_moving())


func _process(delta: float) -> void:
    advance(delta)


## Moves the leader and every model up to `delta` seconds' worth toward
## their targets.
func advance(delta: float) -> void:
    var old_position := position
    position = position.move_toward(target_position, move_speed * delta)
    for i in _shown_offsets.size():
        var shown_world := _shown_offsets[i] + old_position
        var target_world := model_offsets[i] + target_position
        _shown_offsets[i] = shown_world.move_toward(target_world, move_speed * delta) - position
        if position == target_position and _shown_offsets[i].is_equal_approx(model_offsets[i]):
            _shown_offsets[i] = model_offsets[i]
    queue_redraw()
    if not is_moving():
        set_process(false)


## Jumps straight to the targets, e.g. when first placed.
func snap_to_target() -> void:
    position = target_position
    _shown_offsets = model_offsets.duplicate()
    queue_redraw()
    set_process(false)


func is_moving() -> bool:
    return position != target_position or _shown_offsets != model_offsets


func get_squad_id() -> StringName:
    return state.squad_id if state else &""


func get_player() -> int:
    return state.get_player() if state else 0


## True if `local_point` (in this token's local pixels) is on one of the
## squad's model bases as drawn.
func contains_local_point(local_point: Vector2) -> bool:
    for i in _shown_offsets.size():
        if local_point.distance_to(_shown_offsets[i]) <= _radius_of(i) + CLICK_MARGIN:
            return true
    return false


func _radius_of(i: int) -> float:
    return model_radii[i] if i < model_radii.size() else radius


func _draw() -> void:
    var color: Color = PLAYER_COLORS.get(get_player(), NEUTRAL_COLOR)
    if activation_display == ActivationDisplay.SPENT or activation_display == ActivationDisplay.ENGAGED:
        color = color.lerp(NEUTRAL_COLOR, 0.6).darkened(0.35)
    for i in _shown_offsets.size():
        var r := _radius_of(i)
        draw_circle(_shown_offsets[i], r, color.darkened(0.45))
        draw_circle(_shown_offsets[i], maxf(r - 2.0, 1.0), color)
    if _shown_offsets.is_empty():
        return
    var leader := _shown_offsets[0]
    draw_circle(leader, maxf(radius - 4.0, 1.0), color.lightened(0.35), false, 2.0)
    if activation_display == ActivationDisplay.ACTIVE:
        draw_circle(leader, radius + 9.0, ACTIVE_COLOR, false, 2.0)
    elif activation_display == ActivationDisplay.ENGAGED:
        # Committed to an engagement: unavailable until the Assault phase.
        for i in 8:
            var from := TAU * i / 8.0
            draw_arc(leader, radius + 9.0, from, from + TAU / 16.0, 4, ENGAGED_COLOR, 2.0)
    if selected:
        draw_circle(leader, radius + 5.0, SELECTION_COLOR, false, 3.0)
    if morale_status == SquadState.MoraleStatus.SHAKEN:
        draw_arc(leader, radius + 2.0, PI, TAU, 16, SHAKEN_COLOR, 4.0)
    elif morale_status == SquadState.MoraleStatus.BROKEN:
        var r := radius * 0.7
        draw_line(leader + Vector2(-r, -r), leader + Vector2(r, r), BROKEN_COLOR, 3.0)
        draw_line(leader + Vector2(-r, r), leader + Vector2(r, -r), BROKEN_COLOR, 3.0)
