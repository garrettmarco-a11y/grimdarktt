extends Resource
class_name TerrainPiece
## One kind of terrain. Every property is independent: none is implied by
## another or by a terrain category. Each of the three polygons is optional and
## separately editable; a piece may reuse the same coordinates in several.
##
##   - footprint: area a model stands in (inclusive boundary). Provides cover
##     and difficult movement. Empty means no footprint. Footprints of placed
##     pieces may touch but never overlap (enforced by TerrainMap).
##   - los_blocker: geometry that obstructs line of sight. Empty means none.
##   - impassable_area: area models may not move through. Empty means none.
##   - difficult: movement through the footprint's interior costs double.
##   - cover: protection for models in the footprint; a piece without a
##     footprint gives no cover.
## Polygons are in local board units around the placement point.

enum Cover { NONE, LIGHT, HEAVY }

@export var terrain_name: String = ""
@export var footprint := PackedVector2Array()
@export var los_blocker := PackedVector2Array()
@export var impassable_area := PackedVector2Array()
@export var difficult := false
@export var cover := Cover.NONE


static func cover_name(value: Cover) -> String:
    return ["None", "Light", "Heavy"][value]
