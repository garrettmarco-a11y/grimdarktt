extends Node2D
class_name TerrainLayer
## Draws the battlefield's terrain from the TerrainMap, beneath the movement
## overlay and squad tokens. Visual only: it owns no terrain data or rules.
##
## Footprints are translucent fills tinted by cover (none, light, heavy);
## difficult footprints get a dashed outline; line-of-sight geometry is a dark
## fill; impassable areas get a red outline. Each is drawn from its own polygon. Must be a direct child of a
## GameBoard.

const FOOTPRINT_COLORS := [Color(0.55, 0.5, 0.35, 0.22), Color(0.35, 0.6, 0.3, 0.32), Color(0.2, 0.38, 0.22, 0.5)]
const OUTLINE_COLOR := Color(0.85, 0.8, 0.6, 0.6)
const BLOCKER_COLOR := Color(0.08, 0.08, 0.09, 0.7)
const BLOCKER_OUTLINE := Color(0.5, 0.5, 0.55, 0.9)
const IMPASSABLE_COLOR := Color(0.85, 0.25, 0.2, 0.9)

var _terrain: TerrainMap


func bind(terrain: TerrainMap) -> void:
    _terrain = terrain
    queue_redraw()


func _draw() -> void:
    var board := get_parent() as GameBoard
    if board == null or _terrain == null:
        return
    for placed in _terrain.get_placed():
        var piece := placed.piece
        # Blockers first, so a footprint's cover tint and outline stay visible.
        if placed.los_blocker.size() >= 3:
            var blocker := _to_pixels(board, placed.los_blocker)
            draw_colored_polygon(blocker, BLOCKER_COLOR)
            _outline(blocker, BLOCKER_OUTLINE, false)
        if placed.footprint.size() >= 3:
            var footprint := _to_pixels(board, placed.footprint)
            draw_colored_polygon(footprint, FOOTPRINT_COLORS[piece.cover])
            _outline(footprint, OUTLINE_COLOR, piece.difficult)
        if placed.impassable_area.size() >= 3:
            _outline(_to_pixels(board, placed.impassable_area), IMPASSABLE_COLOR, false, 2.5)


func _outline(polygon: PackedVector2Array, color: Color, dashed: bool, width := 1.5) -> void:
    for i in polygon.size():
        var a := polygon[i]
        var b := polygon[(i + 1) % polygon.size()]
        if dashed:
            draw_dashed_line(a, b, color, width, 6.0)
        else:
            draw_line(a, b, color, width)


static func _to_pixels(board: GameBoard, polygon: PackedVector2Array) -> PackedVector2Array:
    var pixels := PackedVector2Array()
    for point in polygon:
        pixels.append(board.units_to_pixels(point))
    return pixels
