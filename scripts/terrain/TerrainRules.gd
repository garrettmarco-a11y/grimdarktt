extends RefCounted
class_name TerrainRules
## Terrain combat rules as pure functions: model and squad cover, the squad's
## majority armour save, and the cover modifiers.
##
## Rules (approved by the project lead):
##   - A model's cover is that of the footprint it stands in. Footprints never
##     overlap; on a boundary shared by touching footprints the less protective
##     cover applies (TerrainMap.cover_at).
##   - A squad's cover is the category holding most of its living models; ties
##     go to the less protective category (NONE < LIGHT < HEAVY).
##   - A squad's armour save is the most common among its living models; ties go
##     to the worse save (higher target number; 0, no save, is worst).
##   - LIGHT and HEAVY cover give +1 to armour saves; HEAVY also gives -1 to
##     enemy hit rolls. Both are always recalculated from current positions.


static func model_cover(state: SquadState, model: ModelState, terrain: TerrainMap) -> TerrainPiece.Cover:
    if terrain == null:
        return TerrainPiece.Cover.NONE
    return terrain.cover_at(state.get_model_position(model))


## Living models per cover category: [none, light, heavy].
static func cover_counts(state: SquadState, terrain: TerrainMap) -> Array[int]:
    var counts: Array[int] = [0, 0, 0]
    for model in state.get_living_models():
        counts[model_cover(state, model, terrain)] += 1
    return counts


static func squad_cover(state: SquadState, terrain: TerrainMap) -> TerrainPiece.Cover:
    var counts := cover_counts(state, terrain)
    var best := TerrainPiece.Cover.NONE
    for cover in [TerrainPiece.Cover.LIGHT, TerrainPiece.Cover.HEAVY]:
        if counts[cover] > counts[best]:
            best = cover
    return best


static func model_armor_save(state: SquadState, model: ModelState) -> int:
    var override := model.definition.armor_save_override if model.definition else -1
    if override >= 0:
        return override
    return state.data.profile.armor_save if state.data and state.data.profile else 0


## The squad's armour save: the most common among living models, ties to the
## worse save. A squad without living models falls back to its profile.
static func majority_armor_save(state: SquadState) -> int:
    var counts := {}
    for model in state.get_living_models():
        var save := model_armor_save(state, model)
        counts[save] = counts.get(save, 0) + 1
    if counts.is_empty():
        return state.data.profile.armor_save if state.data and state.data.profile else 0
    var best: int = counts.keys()[0]
    for save in counts:
        if counts[save] > counts[best] or (counts[save] == counts[best] and _save_rank(save) > _save_rank(best)):
            best = save
    return best


## Added to the attacker's hit target.
static func cover_hit_modifier(cover: TerrainPiece.Cover) -> int:
    return 1 if cover == TerrainPiece.Cover.HEAVY else 0


## Subtracted from the defender's save target.
static func cover_save_bonus(cover: TerrainPiece.Cover) -> int:
    return 1 if cover != TerrainPiece.Cover.NONE else 0


## Larger is worse; no save (0) ranks worst.
static func _save_rank(save: int) -> int:
    return 7 if save <= 0 else save
