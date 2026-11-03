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
## Authoritative board position of the model's centre, in board units. Visual
## tokens follow it; nothing reads positions back from them.
var position := Vector2.ZERO
## Where the model stood when the current turn's movement began.
var turn_start_position := Vector2.ZERO
## Movement allowance this model has spent this turn: the summed cost of every
## path it has actually travelled (difficult terrain counted double).
var movement_used := 0.0

var _model_id: int
var _definition: SquadModel


func _init(id: int, model_definition: SquadModel, wounds: int, start_position: Vector2) -> void:
    _model_id = id
    _definition = model_definition
    wounds_remaining = wounds
    position = start_position
    turn_start_position = start_position


## Radius of the model's circular base, in board units.
func get_base_radius() -> float:
    return _definition.base_radius if _definition else SquadModel.DEFAULT_BASE_RADIUS


## The model's formation slot: where it stands relative to the squad's other
## slots, from its definition. Used only as a movement target.
func get_formation_slot() -> Vector2:
    return _definition.formation_offset if _definition else Vector2.ZERO


func get_model_name() -> String:
    return _definition.model_name if _definition else ""


func get_weapon() -> WeaponProfile:
    return _definition.weapon if _definition else null


func get_melee_weapon() -> WeaponProfile:
    return _definition.melee_weapon if _definition else null
