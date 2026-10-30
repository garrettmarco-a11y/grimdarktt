@tool
extends Node2D
class_name GameBoard
## The battlefield play area: a bounded rectangle drawn procedurally with a
## measurement grid.
##
## Positions on the board are continuous, in board distance units, with the
## origin at the board's top-left corner. The grid is visual guidance only and
## never constrains positions. This node has no turn or rules logic.

## Board size in board distance units. Placeholder until the project lead
## sets the battlefield dimensions.
@export var board_size := Vector2(48.0, 32.0):
    set(value):
        board_size = value
        queue_redraw()
## Pixels drawn per board distance unit. Placeholder until the unit scale is set.
@export_range(1.0, 100.0, 0.5) var pixels_per_unit := 20.0:
    set(value):
        pixels_per_unit = value
        queue_redraw()
## Spacing of the faint grid lines, in board distance units.
@export_range(0.25, 24.0, 0.25) var minor_grid_step := 1.0:
    set(value):
        minor_grid_step = value
        queue_redraw()
## Spacing of the stronger grid lines, in board distance units.
@export_range(0.25, 24.0, 0.25) var major_grid_step := 6.0:
    set(value):
        major_grid_step = value
        queue_redraw()

@export_group("Colors")
@export var surface_color := Color(0.16, 0.15, 0.12):
    set(value):
        surface_color = value
        queue_redraw()
@export var minor_grid_color := Color(1.0, 1.0, 1.0, 0.04):
    set(value):
        minor_grid_color = value
        queue_redraw()
@export var major_grid_color := Color(1.0, 1.0, 1.0, 0.12):
    set(value):
        major_grid_color = value
        queue_redraw()
@export var border_color := Color(0.62, 0.52, 0.34):
    set(value):
        border_color = value
        queue_redraw()
@export var border_width := 3.0:
    set(value):
        border_width = value
        queue_redraw()


## The playable area in this node's local pixel coordinates.
func get_board_rect() -> Rect2:
    return Rect2(Vector2.ZERO, units_to_pixels(board_size))


func units_to_pixels(units: Vector2) -> Vector2:
    return units * pixels_per_unit


func pixels_to_units(pixels: Vector2) -> Vector2:
    return pixels / pixels_per_unit


## True if `point` (in board distance units) lies on or inside the board edge.
func contains_point(point: Vector2) -> bool:
    return point.x >= 0.0 and point.y >= 0.0 and point.x <= board_size.x and point.y <= board_size.y


## Positions of interior grid lines along an axis of `length`, in board units.
## The board edges are excluded; they are drawn as the border.
static func grid_line_positions(step: float, length: float) -> PackedFloat32Array:
    var positions := PackedFloat32Array()
    if step <= 0.0:
        return positions
    var count := int(floor(length / step + 0.0001))
    for i in range(1, count + 1):
        var line_pos := i * step
        if line_pos < length - 0.0001:
            positions.append(line_pos)
    return positions


func _draw() -> void:
    var rect := get_board_rect()
    draw_rect(rect, surface_color)
    _draw_grid(minor_grid_step, minor_grid_color, major_grid_step)
    _draw_grid(major_grid_step, major_grid_color, 0.0)
    draw_rect(rect, border_color, false, border_width)


## Draws grid lines every `step` units, skipping lines that fall on `skip_step`.
func _draw_grid(step: float, color: Color, skip_step: float) -> void:
    var size := get_board_rect().size
    for x in grid_line_positions(step, board_size.x):
        if not _is_multiple(x, skip_step):
            var px := x * pixels_per_unit
            draw_line(Vector2(px, 0.0), Vector2(px, size.y), color)
    for y in grid_line_positions(step, board_size.y):
        if not _is_multiple(y, skip_step):
            var py := y * pixels_per_unit
            draw_line(Vector2(0.0, py), Vector2(size.x, py), color)


static func _is_multiple(value: float, step: float) -> bool:
    if step <= 0.0:
        return false
    var ratio := value / step
    return absf(ratio - roundf(ratio)) < 0.0001
