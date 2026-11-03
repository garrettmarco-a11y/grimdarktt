extends RefCounted
class_name SquadState
## A squad's current condition on the battlefield (runtime only, never saved).
##
## SquadData describes what the squad is; SquadState describes where it is now.
## Statistics are read from `data` and never copied here. Together with its
## ModelStates this is the authoritative source for model positions, movement
## tracking and casualties; visual tokens follow it. Movement rules live in
## MovementRules / SquadMover / MovementController, damage rules in
## DamageRules / ShootingController.
##
## Every model has its own authoritative position (ModelState.position). The
## squad's anchor (board_position) is the current leader's position: the first
## surviving model in the original model order.

signal position_changed(state: SquadState)
## Emitted when movement tracking (turn start, allowance or completion) changes.
signal movement_changed(state: SquadState)
## Emitted when a model takes damage, is removed, or the leader changes.
signal models_changed(state: SquadState)
## Emitted when morale_status or a per-turn morale restriction changes.
signal morale_changed(state: SquadState)

## Morale condition. Broken takes precedence over Shaken; they never stack.
enum MoraleStatus { STEADY, SHAKEN, BROKEN }

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
## The squad's anchor: the current leader's position, in board units. Setting
## it places the whole squad rigidly (see place_formation); that is for
## deployment and tests only and never used by movement rules.
var board_position: Vector2:
    get:
        var leader := get_leader()
        return leader.position if leader else _anchor
    set(value):
        place_formation(value)

## Where the leader stood when the current turn's movement began.
var turn_start_position: Vector2:
    get:
        var leader := get_leader()
        return leader.turn_start_position if leader else _turn_start
## Movement allowance per model this turn, in board units of cost.
var movement_allowance := 0.0
## True once the squad may receive no further move orders this turn.
var movement_complete := false
## Movement allowance the leader has spent this turn (see ModelState).
var movement_used: float:
    get:
        var leader := get_leader()
        return leader.movement_used if leader else _movement_used
## Straight-line distance from the leader's turn-start position to its position.
var distance_moved: float:
    get:
        return turn_start_position.distance_to(board_position)
## True once the squad has lost a model since its last Morale phase activation.
var lost_models_since_morale := false
## Current morale condition; changed by MoraleController.
var morale_status := MoraleStatus.STEADY:
    set(value):
        if value == morale_status:
            return
        morale_status = value
        morale_changed.emit(self)
## True for the rest of the turn after consolidating or taking a rally test:
## the squad may not shoot or initiate an assault. Reset at each turn start.
var morale_restricted_this_turn := false:
    set(value):
        if value == morale_restricted_this_turn:
            return
        morale_restricted_this_turn = value
        morale_changed.emit(self)
## True once a Broken squad has made its rally test this turn.
var rally_attempted_this_turn := false

var _squad_id: StringName
var _data: SquadData
var _models: Array[ModelState] = []
## Anchor, turn start and movement used when there is no leader (a squad with
## no models, or after the last model is removed: the last leader's position).
var _anchor := Vector2.ZERO
var _turn_start := Vector2.ZERO
var _movement_used := 0.0


func _init(squad_data: SquadData, start_position := Vector2.ZERO) -> void:
    _data = squad_data
    _squad_id = squad_data.squad_id if squad_data else &""
    _anchor = start_position
    _turn_start = start_position
    if _data:
        var wounds := _data.profile.wounds if _data.profile else 0
        var leader_slot := _data.models[0].formation_offset if not _data.models.is_empty() else Vector2.ZERO
        for i in _data.models.size():
            var definition := _data.models[i]
            _models.append(ModelState.new(i, definition, wounds, start_position + definition.formation_offset - leader_slot))


## Starts a new turn's movement for every model from where it stands, each
## with `allowance`.
func begin_turn_movement(allowance: float) -> void:
    for model in _models:
        model.turn_start_position = model.position
        model.movement_used = 0.0
    _turn_start = _anchor
    _movement_used = 0.0
    movement_allowance = allowance
    movement_complete = false
    movement_changed.emit(self)


## Places the whole squad rigidly so that its leader stands at `anchor`: every
## model keeps its position relative to the leader. Deployment and test setup
## only; it checks nothing and is never used for rules movement.
func place_formation(anchor: Vector2) -> void:
    var shift := anchor - board_position
    if shift == Vector2.ZERO:
        return
    for model in _models:
        model.position += shift
    _anchor += shift
    position_changed.emit(self)


## Moves models individually. `moves` maps a living model's id to
## [new position, cost of the path it travelled]; each cost is added to that
## model's movement_used. `complete` records whether the squad may move again
## this turn. The caller (MovementController / MoraleController) has resolved
## the paths with SquadMover, which guarantees legal positions.
func apply_model_moves(moves: Dictionary, complete: bool) -> void:
    for model_id in moves:
        var model := get_model(model_id)
        if model == null or model.removed:
            push_error("SquadState.apply_model_moves: model %d is not a living model" % model_id)
            continue
        model.position = moves[model_id][0]
        model.movement_used += moves[model_id][1]
    movement_complete = complete
    position_changed.emit(self)
    movement_changed.emit(self)


## Caps this turn's allowance at `allowance` (never raises it), e.g. half
## movement after consolidating or rallying.
func limit_movement_allowance(allowance: float) -> void:
    if allowance >= movement_allowance:
        return
    movement_allowance = allowance
    movement_changed.emit(self)


func get_remaining_movement() -> float:
    return maxf(movement_allowance - movement_used, 0.0)


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


## Original model count, removed models included.
func get_starting_model_count() -> int:
    return _models.size()


## True if fewer than half the starting models survive (exactly half is not).
func is_below_half_strength() -> bool:
    return get_model_count() * 2 < get_starting_model_count()


func is_destroyed() -> bool:
    return not _models.is_empty() and get_leader() == null


## Authoritative board position of `model`'s centre.
func get_model_position(model: ModelState) -> Vector2:
    return model.position


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
        if was_leader:
            _remember_leader(model)
        model.removed = true
        lost_models_since_morale = true
    models_changed.emit(self)
    return model.removed


## Removes every surviving model at once, e.g. when the squad falls back off
## the battlefield. No leader is promoted. The caller removes the squad from
## the BattleState.
func remove_all_models() -> void:
    var any := false
    var leader := get_leader()
    if leader:
        _remember_leader(leader)
    for model in _models:
        if not model.removed:
            model.removed = true
            model.wounds_remaining = 0
            any = true
    if any:
        lost_models_since_morale = true
        models_changed.emit(self)


## Clears the loss flag once the squad's Morale phase opportunity is resolved.
func clear_morale_losses() -> void:
    lost_models_since_morale = false


## Keeps the departing leader's position and movement as the squad's anchor
## for when no model is left. A surviving model takes over simply by being the
## first living model: no model moves, and each keeps its own turn-start
## position and movement used.
func _remember_leader(leader: ModelState) -> void:
    _anchor = leader.position
    _turn_start = leader.turn_start_position
    _movement_used = leader.movement_used
