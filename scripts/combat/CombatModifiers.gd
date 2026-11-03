extends RefCounted
class_name CombatModifiers
## The one place attack modifiers combine, shared by shooting and assault.
##
##   hit target = Quality + Shaken (+1) + target in HEAVY cover (+1)
## A higher target is harder; 7+ cannot hit (no automatic hit on a 6).


static func hit_target(attacker: SquadState, target_cover: TerrainPiece.Cover) -> int:
    return MoraleRules.hit_target(attacker) + TerrainRules.cover_hit_modifier(target_cover)
