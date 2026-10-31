extends RefCounted
class_name LineOfSight
## Line-of-sight queries on the battlefield, in board units.
##
## Blockers are axis-aligned rectangles. The battlefield has no terrain yet, so
## in play there are none and every line is clear. Cover and partial
## visibility are not modelled.

var _blockers: Array[Rect2] = []


func add_blocker(rect: Rect2) -> void:
    _blockers.append(rect)


func clear_blockers() -> void:
    _blockers.clear()


## True if the segment from `from` to `to` crosses no blocker.
func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
    for rect in _blockers:
        if _segment_hits_rect(from, to, rect):
            return false
    return true


static func _segment_hits_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
    if rect.has_point(from) or rect.has_point(to):
        return true
    var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
    for i in 4:
        if Geometry2D.segment_intersects_segment(from, to, corners[i], corners[(i + 1) % 4]) != null:
            return true
    return false
