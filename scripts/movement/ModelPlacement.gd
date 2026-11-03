extends RefCounted
class_name ModelPlacement
## Physical placement of model bases, as pure functions: base overlap, board
## edges, impassable terrain, swept movement and whole-layout validation.
##
## Rules (approved by the project lead):
##   - Every model has a circular base (SquadModel.base_radius). The bases of
##     two living models, of any squads, may touch but never overlap: centres
##     closer than the sum of the radii (less EPSILON) is an overlap.
##   - A base must lie entirely on the battlefield.
##   - A base may touch but not overlap an impassable_area. Footprints and
##     line-of-sight geometry never obstruct bases.
##   - Removed models occupy no space.

## Floating-point allowance for contact, in board units. Positions are stored
## as float32 Vector2s: two bases placed in mathematically exact contact on a
## 48 x 32 board compute up to ~0.000004 apart from exact, about half of them
## *below* the radius sum. Without an allowance exact contact would often read
## as overlap. This is the only contact tolerance: order validation, movement
## and layout validation all use it, so they always agree. It is not a rules
## allowance: movement never aims inside it (SquadMover stops approaching
## models at exact computed contact), and any overlap deeper than it is real
## and always rejected.
const CONTACT_TOLERANCE := 0.00001


## True if two bases overlap (touching is allowed).
static func bases_overlap(a: Vector2, a_radius: float, b: Vector2, b_radius: float) -> bool:
    return a.distance_to(b) < a_radius + b_radius - CONTACT_TOLERANCE


## True if a base moving in a straight line from `from` to `to` would overlap a
## stationary base at `other` anywhere on the way, its end included.
static func path_hits_base(from: Vector2, to: Vector2, radius: float, other: Vector2, other_radius: float,
        tolerance := CONTACT_TOLERANCE) -> bool:
    var contact := radius + other_radius - tolerance
    return TerrainGeometry.distance_to_segment(other, from, to) < contact or to.distance_to(other) < contact


## True if the whole base lies on a board of `board_size` (edges may touch,
## within `tolerance`).
static func base_on_board(center: Vector2, radius: float, board_size: Vector2, tolerance := CONTACT_TOLERANCE) -> bool:
    return center.x >= radius - tolerance and center.y >= radius - tolerance \
        and center.x <= board_size.x - radius + tolerance and center.y <= board_size.y - radius + tolerance


## Every pair of living models whose bases overlap, across `squads`, as
## [squad, model, other squad, other model].
static func find_overlaps(squads: Array[SquadState]) -> Array:
    var placed := _living(squads)
    var overlaps := []
    for i in placed.size():
        for j in range(i + 1, placed.size()):
            var a: ModelState = placed[i][1]
            var b: ModelState = placed[j][1]
            if bases_overlap(a.position, a.get_base_radius(), b.position, b.get_base_radius()):
                overlaps.append([placed[i][0], a, placed[j][0], b])
    return overlaps


## Problems with the living models' placement: overlapping bases, bases off a
## board of `board_size`, and bases overlapping impassable terrain. Empty if
## the layout is legal.
static func layout_errors(squads: Array[SquadState], board_size: Vector2, terrain: TerrainMap = null) -> PackedStringArray:
    var errors := PackedStringArray()
    for entry in _living(squads):
        var model: ModelState = entry[1]
        var radius := model.get_base_radius()
        if not base_on_board(model.position, radius, board_size):
            errors.append("%s is not entirely on the battlefield" % describe(entry[0], model))
        if terrain and terrain.base_crosses_impassable(model.position, model.position, radius):
            errors.append("%s overlaps impassable terrain" % describe(entry[0], model))
    for pair in find_overlaps(squads):
        errors.append("%s overlaps %s" % [describe(pair[0], pair[1]), describe(pair[2], pair[3])])
    return errors


## "squad_id model name (#id) at (x, y)" for messages.
static func describe(squad: SquadState, model: ModelState) -> String:
    return "%s %s (#%d) at (%.2f, %.2f)" % [squad.squad_id, model.get_model_name(), model.model_id,
        model.position.x, model.position.y]


static func _living(squads: Array[SquadState]) -> Array:
    var living := []
    for squad in squads:
        for model in squad.get_living_models():
            living.append([squad, model])
    return living
