extends RefCounted
class_name TerrainGeometry
## Polygon geometry for terrain, in board units: point membership, the parts of
## a segment inside a polygon, and placement transforms. Pure functions.
##
## Boundary behaviour (one tolerance, EPSILON, throughout):
##   - A point on a polygon's edge or vertex counts as inside it.
##   - Only the polygon's interior obstructs or slows: a segment that merely
##     touches a vertex or runs exactly along an edge is not inside it.

const EPSILON := 0.001


static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
    return Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point)


static func is_on_boundary(point: Vector2, polygon: PackedVector2Array) -> bool:
    var n := polygon.size()
    for i in n:
        if distance_to_segment(point, polygon[i], polygon[(i + 1) % n]) <= EPSILON:
            return true
    return false


## True if `point` is inside `polygon` or on its boundary.
static func contains_point(polygon: PackedVector2Array, point: Vector2) -> bool:
    if polygon.size() < 3:
        return false
    return is_on_boundary(point, polygon) or Geometry2D.is_point_in_polygon(point, polygon)


## True if `point` is inside `polygon` and not on its boundary.
static func is_strictly_inside(polygon: PackedVector2Array, point: Vector2) -> bool:
    if polygon.size() < 3:
        return false
    return not is_on_boundary(point, polygon) and Geometry2D.is_point_in_polygon(point, polygon)


## The parts of segment a->b inside the polygon's interior, as parameter
## intervals Vector2(t_start, t_end) along the segment (0 at a, 1 at b), in
## order and merged where they touch.
static func interior_intervals(a: Vector2, b: Vector2, polygon: PackedVector2Array) -> Array[Vector2]:
    var intervals: Array[Vector2] = []
    var direction := b - a
    var length := direction.length()
    if polygon.size() < 3 or length <= EPSILON:
        return intervals
    var cuts: Array[float] = [0.0, 1.0]
    var n := polygon.size()
    for i in n:
        var p := polygon[i]
        var q := polygon[(i + 1) % n]
        var hit = Geometry2D.segment_intersects_segment(a, b, p, q)
        if hit != null:
            cuts.append(_param(hit, a, direction))
        # Collinear overlaps are missed above; their end vertices are cuts too.
        if distance_to_segment(p, a, b) <= EPSILON:
            cuts.append(_param(p, a, direction))
    cuts.sort()
    for i in range(cuts.size() - 1):
        var t0 := cuts[i]
        var t1 := cuts[i + 1]
        if (t1 - t0) * length <= EPSILON:
            continue
        if is_strictly_inside(polygon, a + direction * ((t0 + t1) * 0.5)):
            if not intervals.is_empty() and absf(intervals[-1].y - t0) * length <= EPSILON:
                intervals[-1].y = t1
            else:
                intervals.append(Vector2(t0, t1))
    return intervals


## Union of interval lists (each Vector2(t_start, t_end)), sorted and merged.
static func merge_intervals(intervals: Array[Vector2]) -> Array[Vector2]:
    var sorted := intervals.duplicate()
    sorted.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x)
    var merged: Array[Vector2] = []
    for interval in sorted:
        if not merged.is_empty() and interval.x <= merged[-1].y:
            merged[-1].y = maxf(merged[-1].y, interval.y)
        else:
            merged.append(interval)
    return merged


## True if the polygon's interior lies across segment a->b somewhere other
## than a stretch that begins at `a` or ends at `b` (the endpoint's own terrain).
static func blocks_between(a: Vector2, b: Vector2, polygon: PackedVector2Array) -> bool:
    var length := a.distance_to(b)
    if length <= EPSILON:
        return false
    var tolerance := EPSILON / length
    for interval in interior_intervals(a, b, polygon):
        if interval.x > tolerance and interval.y < 1.0 - tolerance:
            return true
    return false


## Area of a simple polygon (absolute value, either winding).
static func polygon_area(polygon: PackedVector2Array) -> float:
    var twice := 0.0
    for i in polygon.size():
        var a := polygon[i]
        var b := polygon[(i + 1) % polygon.size()]
        twice += a.x * b.y - b.x * a.y
    return absf(twice) * 0.5


## True if the two polygons share interior area (more than EPSILON squared).
## Touching along an edge or at a vertex is not an overlap; containment and
## identical polygons are.
static func polygons_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
    if a.size() < 3 or b.size() < 3:
        return false
    var shared := 0.0
    for piece in Geometry2D.intersect_polygons(a, b):
        shared += polygon_area(piece)
    return shared > EPSILON * EPSILON


static func total_length(intervals: Array[Vector2]) -> float:
    var total := 0.0
    for interval in intervals:
        total += interval.y - interval.x
    return total


## `polygon` rotated by `rotation` radians about its local origin, then moved
## to `position`.
static func transform_polygon(polygon: PackedVector2Array, position: Vector2, rotation: float) -> PackedVector2Array:
    var placed := PackedVector2Array()
    for vertex in polygon:
        placed.append(vertex.rotated(rotation) + position)
    return placed


static func _param(point: Vector2, a: Vector2, direction: Vector2) -> float:
    return clampf((point - a).dot(direction) / direction.length_squared(), 0.0, 1.0)
