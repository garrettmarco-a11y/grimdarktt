extends RefCounted
class_name SquadState
## A squad's current condition on the battlefield (runtime only, never saved).
##
## SquadData describes what the squad is; SquadState describes where it is now.
## Statistics are read from `data` and never copied here. This is the
## authoritative source for the squad's position, movement tracking and model
## casualties; visual tokens follow it. Movement rules live in MovementRules /
## MovementController, damage rules in DamageRules / ShootingController.
##
## The squad's anchor (board_position) is the current leader's position: the
## first surviving model in the original model order.

signal position_changed(state: SquadState)
## Emitted when movement tracking (turn start, allowance or completion) changes.
signal movement_changed(state: SquadState)
## Emitted when a model takes damage, is removed, or the leader changes.
signal models_changed(state: SquadState)

## Stable identifier, taken from the squad's data at creation.
var squad_id: StringName:
    get:
        return _squad_id
    set(_value):
        push_error("SquadState.squad_id is read-only")
## The squad's persistent configuration.
var data: SquadData:
    get:
        return _data
    set(_value):
        push_error("SquadState.data is read-only")
## Current position in board distance units (continuous, not snapped).
var board_position := Vector2.ZERO:
    set(value):
        if value == board_position:
            return
        board_position = value
        position_changed.emit(self)

## Where the squad stood when the current turn's movement began.
var turn_start_position := Vector2.ZERO
## Maximum distance from turn_start_position this turn, in board units.
var movement_allowance := 0.0
## True once the squad may not move again this turn.
var movement_complete := false
## Straight-line distance from turn_start_position to the current position.
var distance_moved: float:
    get:
        return turn_start_position.distance_to(board_position)
## True once the squad has lost a model since its last Morale phase activation.
var lost_models_since_morale := false

var _squad_id: StringName
var _data: SquadData
var _models: Array[ModelState] = []


func _init(squad_data: SquadData, start_position := Vector2.ZERO) -> void:
    _data = squad_data
    _squad_id = squad_data.squad_id if squad_data else &""
    board_position = start_position
    turn_start_position = start_position
    if _data:
        var wounds := _data.profile.wounds if _data.profile else 0
        var leader_offset := _data.models[0].formation_offset if not _data.models.is_empty() else Vector2.ZERO
        for i in _data.models.size():
            var definition := _data.models[i]
            _models.append(ModelState.new(i, definition, wounds, definition.formation_offset - leader_offset))


## Starts a new turn's movement from the current position with `allowance`.
func begin_turn_movement(allowance: float) -> void:
    turn_start_position = board_position
    movement_allowance = allowance
    movement_complete = false
    movement_changed.emit(self)


## Moves to `destination` and records whether movement is now complete. The
## caller (MovementController) is responsible for validating the order.
func apply_move(destination: Vector2, complete: bool) -> void:
    board_position = destination
    movement_complete = complete
    movement_changed.emit(self)


func get_remaining_movement() -> float:
    return maxf(movement_allowance - distance_moved, 0.0)


func get_player() -> int:
    return _data.player if _data else 0


## Every model, removed or not, in the original model order.
func get_models() -> Array[ModelState]:
    return _models.duplicate()


## Surviving models, in the original model order.
func get_living_models() -> Array[ModelState]:
    return _models.filter(func(m: ModelState) -> bool: return not m.removed)


## Number of surviving models.
func get_model_count() -> int:
    return get_living_models().size()


## The model with stable id `model_id`, removed or not, or null.
func get_model(model_id: int) -> ModelState:
    return _models[model_id] if model_id >= 0 and model_id < _models.size() else null


## The current leader: the first surviving model in the original order.
func get_leader() -> ModelState:
    for model in _models:
        if not model.removed:
            return model
    return null


## Profile governing the squad's movement: the leader's. Until models carry
## their own profiles every model shares the squad's profile.
func get_leader_profile() -> UnitProfile:
    return _data.profile if _data else null


func is_destroyed() -> bool:
    return not _models.is_empty() and get_leader() == null


## Board position of `model`. Temporary representation: models keep their
## offset from the squad anchor and move rigidly with it.
func get_model_position(model: ModelState) -> Vector2:
    return board_position + model.offset


## Applies one point of damage to the living model `model_id`. A model at 0
## wounds is removed; if it was the leader, the next survivor takes over (see
## _promote_leader). The caller (ShootingController) validates the allocation
## with DamageRules first. Returns true if the model was removed.
func take_wound(model_id: int) -> bool:
    var model := get_model(model_id)
    if model == null or model.removed:
        push_error("SquadState.take_wound: model %d is not a living model" % model_id)
        return false
    var was_leader := model == get_leader()
    model.wounds_remaining -= 1
    if model.wounds_remaining <= 0:
        model.wounds_remaining = 0
        model.removed = true
        lost_models_since_morale = true
        if was_leader and get_leader() != null:
            _promote_leader()
    models_changed.emit(self)
    return model.removed


## Clears the loss flag once the squad's Morale phase opportunity is resolved.
func clear_morale_losses() -> void:
    lost_models_since_morale = false


## Moves the anchor to the new leader without moving any model: the anchor and
## the turn-start position shift by the new leader's offset, and every offset is
## rebased on the new leader, so world positions and distance_moved are kept.
func _promote_leader() -> void:
    var shift := get_leader().offset
    for model in _models:
        model.offset -= shift
    turn_start_position += shift
    board_position += shift
