extends RefCounted
class_name LineOfSight
## Line-of-sight queries on the battlefield, in board units.
##
## Obstructions are the TerrainMap's line-of-sight polygons plus any extra
## blockers added directly (rectangles or polygons, e.g. in tests). The
## geometry rule is TerrainGeometry.blocks_between: only obstruction crossed
## between the endpoints counts, so models inside blocking terrain can see out
## and be seen. Cover is not part of line of sight.

var terrain: TerrainMap

var _blockers: Array[PackedVector2Array] = []


func _init(terrain_map: TerrainMap = null) -> void:
    terrain = terrain_map


func add_blocker(rect: Rect2) -> void:
    add_blocker_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
        rect.end, Vector2(rect.position.x, rect.end.y)]))


func add_blocker_polygon(polygon: PackedVector2Array) -> void:
    _blockers.append(polygon)


func clear_blockers() -> void:
    _blockers.clear()


## True if nothing obstructs the segment from `from` to `to`.
func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
    if terrain and terrain.is_segment_blocked(from, to):
        return false
    for polygon in _blockers:
        if TerrainGeometry.blocks_between(from, to, polygon):
            return false
    return true
