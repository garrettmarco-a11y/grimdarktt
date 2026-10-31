extends Node
class_name ShootingController
## Coordinates a shooting order: validates it with ShootingRules, rolls hits,
## wounds and saves, waits for the defender to allocate each unsaved wound,
## applies the damage to the target's SquadState, removes a destroyed squad
## through BattleState, and ends the firing squad's activation through the
## ActivationController. Has no input or drawing code.
##
## While unsaved wounds await allocation the shooter's activation stays open
## (locked) and no new shot is accepted.

signal shot_resolved(result: ShootingResult)
signal shot_rejected(firing: SquadState, target: SquadState, result: ShootingRules.OrderResult)
## The defender must allocate `wounds_left` more unsaved wounds for `result`.
signal allocation_required(result: ShootingResult, wounds_left: int)

var line_of_sight := LineOfSight.new()
var dice := DiceRoller.new()

var _turn_manager: TurnManager
var _activation: ActivationController
var _battle: BattleState
var _pending: ShootingResult
var _wounds_left := 0


func bind(turn_manager: TurnManager, activation: ActivationController, battle: BattleState) -> void:
    _turn_manager = turn_manager
    _activation = activation
    _battle = battle


func is_allocation_pending() -> bool:
    return _pending != null


func get_pending_result() -> ShootingResult:
    return _pending


func get_wounds_left() -> int:
    return _wounds_left


## Orders `firing` to shoot at `target`. A valid order always resolves and
## spends the activation, even if no model can fire; if wounds go unsaved the
## activation ends once the defender has allocated them.
func order_shot(firing: SquadState, target: SquadState) -> ShootingRules.OrderResult:
    var result := ShootingRules.OrderResult.ALLOCATION_PENDING if _pending else \
        ShootingRules.validate_order(firing, target, _turn_manager.current_phase,
            _activation.is_active_squad(firing))
    if result != ShootingRules.OrderResult.OK:
        shot_rejected.emit(firing, target, result)
        return result
    var outcome := ShootingRules.resolve(firing, target, line_of_sight, dice)
    DamageRules.resolve_wounds_and_saves(outcome, dice)
    _wounds_left = outcome.get_unsaved_wounds()
    if _wounds_left > 0 and target.get_model_count() > 0:
        _pending = outcome
        _activation.locked = true
        allocation_required.emit(outcome, _wounds_left)
    else:
        _finish(outcome)
    return result


## The defender allocates one pending unsaved wound to model `model_id` of the
## target squad.
func allocate_wound(model_id: int) -> DamageRules.AllocationResult:
    var target := _pending.target_squad if _pending else null
    var result := DamageRules.validate_allocation(target, model_id, _wounds_left)
    if result != DamageRules.AllocationResult.OK:
        return result
    var allocation := ShootingResult.Allocation.new()
    allocation.model_id = model_id
    allocation.model_name = target.get_model(model_id).get_model_name()
    allocation.removed = target.take_wound(model_id)
    _pending.allocations.append(allocation)
    _wounds_left -= 1
    if target.is_destroyed():
        _pending.wasted_wounds = _wounds_left
        _wounds_left = 0
    if _wounds_left > 0:
        allocation_required.emit(_pending, _wounds_left)
    else:
        var outcome := _pending
        _pending = null
        _finish(outcome)
    return result


func _finish(outcome: ShootingResult) -> void:
    var target := outcome.target_squad
    outcome.models_remaining = target.get_model_count()
    outcome.target_destroyed = target.is_destroyed()
    _activation.locked = false
    if outcome.target_destroyed:
        _battle.remove_squad(target.squad_id)
    shot_resolved.emit(outcome)
    _activation.end_activation()
