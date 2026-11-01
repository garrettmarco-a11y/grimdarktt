extends RefCounted
class_name CasualtyAllocator
## Finishes any attack (shooting or assault) once its hits, wounds and saves
## are rolled: the defender allocates each unsaved wound to a living model of
## the target squad, the damage is applied to its SquadState, a destroyed squad
## is removed through BattleState, and the attacker's activation is ended
## through the ActivationController.
##
## While wounds await allocation the attacker's activation stays open (locked).
## Shared by ShootingController and AssaultController; has no input or drawing
## code.

## The defender must allocate `wounds_left` more unsaved wounds for `result`.
signal allocation_required(result: CombatResult, wounds_left: int)
## The attack is fully resolved; emitted before the attacker's activation ends.
signal resolved(result: CombatResult)

var _activation: ActivationController
var _battle: BattleState
var _pending: CombatResult
var _wounds_left := 0


func bind(activation: ActivationController, battle: BattleState) -> void:
    _activation = activation
    _battle = battle


func is_pending() -> bool:
    return _pending != null


func get_pending_result() -> CombatResult:
    return _pending


func get_wounds_left() -> int:
    return _wounds_left


## Starts allocation for `result`, whose wounds and saves are already rolled.
## With nothing to allocate the attack is finished at once.
func begin(result: CombatResult) -> void:
    _wounds_left = result.get_unsaved_wounds()
    if _wounds_left > 0 and result.target_squad.get_model_count() > 0:
        _pending = result
        _activation.locked = true
        allocation_required.emit(result, _wounds_left)
    else:
        _wounds_left = 0
        _finish(result)


## The defender allocates one pending unsaved wound to model `model_id` of the
## target squad.
func allocate_wound(model_id: int) -> DamageRules.AllocationResult:
    var target := _pending.target_squad if _pending else null
    var result := DamageRules.validate_allocation(target, model_id, _wounds_left)
    if result != DamageRules.AllocationResult.OK:
        return result
    var allocation := CombatResult.Allocation.new()
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


func _finish(outcome: CombatResult) -> void:
    var target := outcome.target_squad
    outcome.models_remaining = target.get_model_count()
    outcome.target_destroyed = target.is_destroyed()
    _activation.locked = false
    if outcome.target_destroyed:
        _battle.remove_squad(target.squad_id)
    resolved.emit(outcome)
    # A listener may already have removed the attacker (ending its activation
    # through BattleState); never end an activation twice.
    if _activation.is_active_squad(outcome.attacker_squad):
        _activation.end_activation()
