extends Resource
class_name SquadModel
## One model in a squad's starting composition.
##
## Minimal for now: a name, an optional ranged weapon, an optional melee
## weapon, its base size and its formation slot. The squad's UnitProfile still
## supplies the model's characteristics.

## Base radius every model uses unless its definition says otherwise.
const DEFAULT_BASE_RADIUS := 0.5

@export var model_name: String = ""
## The model's ranged weapon, or null if it has none.
@export var weapon: WeaponProfile
## The model's melee weapon, or null if it has none. Its range is unused.
@export var melee_weapon: WeaponProfile
## Armour save for this model alone (e.g. different equipment); -1 uses the
## squad profile's armor_save.
@export var armor_save_override := -1
## Formation slot relative to the squad's anchor (the leader), in board units:
## where the model starts, and where it aims when the squad moves.
@export var formation_offset := Vector2.ZERO
## Radius of the model's circular base, in board units. Bases of living models
## may touch but never overlap.
@export var base_radius := DEFAULT_BASE_RADIUS
