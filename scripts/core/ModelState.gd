extends RefCounted
class_name ModelState
## One model's condition in battle (runtime only, never saved).
##
## Battle damage lives here, never on the shared SquadModel / UnitProfile
## Resources. Created by SquadState from its SquadData.

## Stable id for the whole battle: the model's index in the squad's original
## model order.
var model_id: int:
    get:
        return _model_id
    set(_value):
        push_error("ModelState.model_id is read-only")
## The model's static definition.
var definition: SquadModel:
    get:
        return _definition
    set(_value):
        push_error("ModelState.definition is read-only")
var wounds_remaining := 0
var removed := false
## Position relative to the squad's anchor (the current leader), in board units.
var offset := Vector2.ZERO

var _model_id: int
var _definition: SquadModel


func _init(id: int, model_definition: SquadModel, wounds: int, anchor_offset: Vector2) -> void:
    _model_id = id
    _definition = model_definition
    wounds_remaining = wounds
    offset = anchor_offset


func get_model_name() -> String:
    return _definition.model_name if _definition else ""


func get_weapon() -> WeaponProfile:
    return _definition.weapon if _definition else null


func get_melee_weapon() -> WeaponProfile:
    return _definition.melee_weapon if _definition else null
