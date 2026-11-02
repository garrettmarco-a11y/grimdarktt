extends RefCounted
class_name TerrainMap
## The battlefield's placed terrain (runtime, static for the battle) and its
## geometry queries, in board units. Independent of BattleState and of any
## visual node; rules and views receive it by injection.


## One placed piece with its polygons in board coordinates.
class Placed:
    var piece: TerrainPiece
    var footprint := PackedVector2Array()
    var los_blocker := PackedVector2Array()


var _placed: Array[Placed] = []


func _init(setups: Array[TerrainSetup] = []) -> void:
    for setup in setups:
        if setup and setup.piece:
            add(setup.piece, setup.position, deg_to_rad(setup.rotation_degrees))


## Places `piece` with its local origin at `position`, rotated `rotation` radians.
func add(piece: TerrainPiece, position := Vector2.ZERO, rotation := 0.0) -> void:
    var placed := Placed.new()
    placed.piece = piece
    placed.footprint = TerrainGeometry.transform_polygon(piece.footprint, position, rotation)
    placed.los_blocker = TerrainGeometry.transform_polygon(piece.los_blocker, position, rotation)
    _placed.append(placed)


func get_placed() -> Array[Placed]:
    return _placed


## Pieces whose footprint contains `point` (boundary included).
func pieces_at(point: Vector2) -> Array[TerrainPiece]:
    var pieces: Array[TerrainPiece] = []
    for placed in _placed:
        if TerrainGeometry.contains_point(placed.footprint, point):
            pieces.append(placed.piece)
    return pieces


## Cover for a model at `point`: the best cover among the footprints containing it.
func cover_at(point: Vector2) -> TerrainPiece.Cover:
    var best := TerrainPiece.Cover.NONE
    for piece in pieces_at(point):
        best = maxi(best, piece.cover) as TerrainPiece.Cover
    return best


## True if any line-of-sight geometry obstructs the segment from `from` to `to`.
## Only geometry crossed between the endpoints counts: the stretch of a
## polygon that contains an endpoint is ignored, so a model inside terrain can
## see out and be seen, and two models inside the same terrain see each other.
## Grazing a vertex or running along an edge does not obstruct.
func is_segment_blocked(from: Vector2, to: Vector2) -> bool:
    for placed in _placed:
        if TerrainGeometry.blocks_between(from, to, placed.los_blocker):
            return true
    return false


## Movement cost of a straight move from `from` to `to`: distance outside
## difficult terrain costs 1 per board unit, distance inside it costs 2.
## Overlapping difficult pieces do not stack.
func movement_cost(from: Vector2, to: Vector2) -> float:
    var length := from.distance_to(to)
    var inside: Array[Vector2] = []
    for placed in _placed:
        if placed.piece.difficult:
            inside.append_array(TerrainGeometry.interior_intervals(from, to, placed.footprint))
    return length * (1.0 + TerrainGeometry.total_length(TerrainGeometry.merge_intervals(inside)))


## True if a straight move from `from` to `to` passes through any part of an
## impassable piece (its footprint or line-of-sight geometry).
func crosses_impassable(from: Vector2, to: Vector2) -> bool:
    for placed in _placed:
        if not placed.piece.impassable:
            continue
        for polygon in [placed.footprint, placed.los_blocker]:
            if not TerrainGeometry.interior_intervals(from, to, polygon).is_empty():
                return true
    return false
