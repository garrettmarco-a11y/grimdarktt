extends Node2D
class_name MovementOverlay
## Draws movement guidance for the selected squad under the squad tokens: its
## movement range from the turn-start position, the line it has moved this
## turn, and a brief marker where an order was rejected.
##
## Must be a direct child of a GameBoard. Reads SquadState; changes nothing.

const RANGE_COLOR := Color(1.0, 0.86, 0.35, 0.10)
const RANGE_EDGE_COLOR := Color(1.0, 0.86, 0.35, 0.45)
const PATH_COLOR := Color(1.0, 0.86, 0.35, 0.8)
const REJECT_COLOR := Color(1.0, 0.3, 0.25)
## Seconds a rejected-order marker stays visible.
const REJECT_DURATION := 1.0

var _squad: SquadState
var _orders_enabled := true
var _reject_point := Vector2.ZERO
var _reject_time_left := 0.0


## Shows guidance for `state`, or nothing when it is null.
func show_squad(state: SquadState) -> void:
    if _squad:
        _squad.position_changed.disconnect(_on_squad_changed)
        _squad.movement_changed.disconnect(_on_squad_changed)
    _squad = state
    if _squad:
        _squad.position_changed.connect(_on_squad_changed)
        _squad.movement_changed.connect(_on_squad_changed)
    queue_redraw()


## Range guidance is only drawn while move orders can be given.
func set_orders_enabled(enabled: bool) -> void:
    _orders_enabled = enabled
    queue_redraw()


## Marks `board_point` (board units) as a rejected destination.
func show_rejected(board_point: Vector2) -> void:
    _reject_point = board_point
    _reject_time_left = REJECT_DURATION
    set_process(true)
    queue_redraw()


func is_showing_rejection() -> bool:
    return _reject_time_left > 0.0


func _ready() -> void:
    set_process(false)


func _process(delta: float) -> void:
    _reject_time_left = maxf(_reject_time_left - delta, 0.0)
    if _reject_time_left == 0.0:
        set_process(false)
    queue_redraw()


func _on_squad_changed(_state: SquadState) -> void:
    queue_redraw()


func _draw() -> void:
    var board := get_parent() as GameBoard
    if board == null:
        return
    if _squad and _orders_enabled:
        var start := board.units_to_pixels(_squad.turn_start_position)
        var current := board.units_to_pixels(_squad.board_position)
        if not _squad.movement_complete:
            var radius := _squad.movement_allowance * board.pixels_per_unit
            draw_circle(start, radius, RANGE_COLOR)
            draw_circle(start, radius, RANGE_EDGE_COLOR, false, 1.5)
        if start != current:
            draw_circle(start, 3.0, PATH_COLOR)
            draw_line(start, current, PATH_COLOR, 2.0)
    if _reject_time_left > 0.0:
        var p := board.units_to_pixels(_reject_point)
        var color := REJECT_COLOR
        color.a = _reject_time_left / REJECT_DURATION
        draw_line(p + Vector2(-8, -8), p + Vector2(8, 8), color, 3.0)
        draw_line(p + Vector2(-8, 8), p + Vector2(8, -8), color, 3.0)
