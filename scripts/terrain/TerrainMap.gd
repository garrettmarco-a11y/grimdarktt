extends RefCounted
class_name TerrainMap
## The battlefield's placed terrain (runtime, static for the battle) and its
## geometry queries, in board units. Independent of BattleState and of any
## visual node; rules and views receive it by injection.
##
## Footprints may never overlap (touching edges or vertices is allowed). A
## configuration with overlapping footprints is rejected whole, and add()
## refuses a piece that would overlap; `errors` explains why. Line-of-sight
## geometry may overlap anything.


## One placed piece with its polygons in board coordinates.
class Placed:
    var piece: TerrainPiece
    var footprint := PackedVector2Array()
    var los_blocker := PackedVector2Array()
    var impassable_area := PackedVector2Array()


## Why a configuration or piece was refused; empty while the map is valid.
var errors := PackedStringArray()

var _placed: Array[Placed] = []


## Builds the map from `setups`. If any two footprints overlap, the whole
## configuration is rejected: the map stays empty and `errors` names every
## overlapping pair.
func _init(setups: Array[TerrainSetup] = []) -> void:
    var candidates: Array[Placed] = []
    var labels := PackedStringArray()
    for i in setups.size():
        var setup := setups[i]
        if setup and setup.piece:
            candidates.append(_place(setup.piece, setup.position, deg_to_rad(setup.rotation_degrees)))
            labels.append("setup #%d %s at %s" % [i, _name_of(setup.piece), setup.position])
    for i in candidates.size():
        for j in range(i + 1, candidates.size()):
            if TerrainGeometry.polygons_overlap(candidates[i].footprint, candidates[j].footprint):
                _refuse("%s and %s" % [labels[i], labels[j]])
    if errors.is_empty():
        _placed = candidates


func is_valid() -> bool:
    return errors.is_empty()


## Places `piece` with its local origin at `position`, rotated `rotation`
## radians. Refused (returns false, map unchanged) if its footprint would
## overlap one already placed.
func add(piece: TerrainPiece, position := Vector2.ZERO, rotation := 0.0) -> bool:
    var placed := _place(piece, position, rotation)
    for other in _placed:
        if TerrainGeometry.polygons_overlap(placed.footprint, other.footprint):
            _refuse("%s at %s and placed %s" % [_name_of(piece), position, _name_of(other.piece)])
            return false
    _placed.append(placed)
    return true


func get_placed() -> Array[Placed]:
    return _placed


## Pieces whose footprint contains `point` (boundary included). Footprints
## never overlap, so this is at most one piece, or two or more only exactly on
## a boundary they share.
func pieces_at(point: Vector2) -> Array[TerrainPiece]:
    var pieces: Array[TerrainPiece] = []
    for placed in _placed:
        if TerrainGeometry.contains_point(placed.footprint, point):
            pieces.append(placed.piece)
    return pieces


## Cover for a model at `point`: that of the footprint containing it, or NONE.
## Boundary convention: a point exactly on a boundary shared by touching
## footprints takes the less protective of their covers.
func cover_at(point: Vector2) -> TerrainPiece.Cover:
    var pieces := pieces_at(point)
    if pieces.is_empty():
        return TerrainPiece.Cover.NONE
    var cover := pieces[0].cover
    for piece in pieces:
        cover = mini(cover, piece.cover) as TerrainPiece.Cover
    return cover


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
## Footprints cannot overlap; merging only joins pieces that touch.
func movement_cost(from: Vector2, to: Vector2) -> float:
    var length := from.distance_to(to)
    var inside: Array[Vector2] = []
    for placed in _placed:
        if placed.piece.difficult:
            inside.append_array(TerrainGeometry.interior_intervals(from, to, placed.footprint))
    return length * (1.0 + TerrainGeometry.total_length(TerrainGeometry.merge_intervals(inside)))


## True if a straight move from `from` to `to` passes through the interior of
## any impassable area. Only impassable_area counts; footprints and
## line-of-sight geometry never block movement. Touching a vertex or running
## along an edge is not crossing.
func crosses_impassable(from: Vector2, to: Vector2) -> bool:
    for placed in _placed:
        if not TerrainGeometry.interior_intervals(from, to, placed.impassable_area).is_empty():
            return true
    return false


func _place(piece: TerrainPiece, position: Vector2, rotation: float) -> Placed:
    var placed := Placed.new()
    placed.piece = piece
    placed.footprint = TerrainGeometry.transform_polygon(piece.footprint, position, rotation)
    placed.los_blocker = TerrainGeometry.transform_polygon(piece.los_blocker, position, rotation)
    placed.impassable_area = TerrainGeometry.transform_polygon(piece.impassable_area, position, rotation)
    return placed


func _refuse(conflict: String) -> void:
    var message := "Terrain footprints overlap: %s. Move, resize or rotate one so they share no area (touching edges is allowed)." % conflict
    errors.append(message)
    push_error(message)


static func _name_of(piece: TerrainPiece) -> String:
    return "'%s'" % (piece.terrain_name if piece.terrain_name != "" else "unnamed")
