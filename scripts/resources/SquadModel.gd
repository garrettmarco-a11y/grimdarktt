extends Resource
class_name SquadModel
## One model in a squad's starting composition.
##
## Minimal for now: a name, an optional ranged weapon, and where the model
## stands relative to the squad's anchor position. The squad's UnitProfile
## still supplies the model's characteristics.

@export var model_name: String = ""
## The model's ranged weapon, or null if it has none.
@export var weapon: WeaponProfile
## Position relative to the squad's anchor (the leader), in board units.
@export var formation_offset := Vector2.ZERO
