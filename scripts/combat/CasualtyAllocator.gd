extends RefCounted
class_name CasualtyAllocator
## Finishes any attack (shooting or assault) once its hits, wounds and saves
## are rolled: the defender allocates each unsaved wound to a living model of
## the target squad, the damage is applied to its SquadState, a destroyed squad
## is removed through BattleState, and the attacker's activation is ended
## through the ActivationController.
##
## While wounds await allocation the attacker's activation stays open (locked).
## Shared by the ShootingController and the EngagementController (queue mode);
## has no input or drawing code.
##
## Queue mode (enqueue) serves an assault engagement's simultaneous strikes:
## every strike has already been rolled, and each result is then allocated in
## turn by the player owning its target squad. Queue mode never touches an
## activation (neither locking nor ending one), never emits `resolved`, and
## removes squads destroyed by the strikes only once the whole queue is done.
## A strike whose target was already destroyed by an earlier strike in the
## queue, or that has no unsaved wounds, needs no allocation: its wounds are
## recorded as wasted and the queue moves on.

## The defender must allocate `wounds_left` more unsaved wounds for `result`.
signal allocation_required(result: CombatResult, wounds_left: int)
## The attack is fully resolved; emitted before the attacker's activation ends.
signal resolved(result: CombatResult)
## Queue mode: one queued strike's casualties are fully applied.
signal strike_allocated(result: CombatResult)
## Queue mode: every queued strike is allocated and destroyed squads removed.
signal queue_resolved(results: Array[CombatResult])

var _activation: ActivationController
var _battle: BattleState
var _pending: CombatResult
var _wounds_left := 0
## Queue mode: strikes still to allocate, and every strike in this queue.
var _queue: Array[CombatResult] = []
var _queued_all: Array[CombatResult] = []
var _queue_active := false


func bind(activation: ActivationController, battle: BattleState) -> void:
    _activation = activation
    _battle = battle


## True while wounds await allocation, from a single attack or a queue.
func is_pending() -> bool:
    return _pending != null or _queue_active


## True while a queue of simultaneous strikes is being allocated.
func is_queue_active() -> bool:
    return _queue_active


## Strikes in the current queue not yet reached (the pending one excluded).
func get_queued_count() -> int:
    return _queue.size()


## Queue mode: allocates `results` (already rolled, in strike order) one after
## another, each by its target squad's player. Each result is numbered
## (strike_index / strike_count) for the UI. Refused while anything else is
## pending. Emits queue_resolved once all are done; may finish at once if no
## strike needs allocating.
func enqueue(results: Array[CombatResult]) -> bool:
    if is_pending():
        push_error("CasualtyAllocator.enqueue: an allocation is already pending")
        return false
    _queue_active = true
    _queue = results.duplicate()
    _queued_all = results.duplicate()
    for i in _queued_all.size():
        _queued_all[i].strike_index = i + 1
        _queued_all[i].strike_count = _queued_all.size()
    _advance_queue()
    return true


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
    # Melee casualties are settled by the assault-loss test, never by an
    # ordinary Morale-phase test: say so explicitly for each casualty.
    var counts_for_morale := _pending.attack_type != CombatResult.AttackType.MELEE
    allocation.removed = target.take_wound(model_id, counts_for_morale)
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
        if _queue_active:
            _finish_strike(outcome)
            _advance_queue()
        else:
            _finish(outcome)
    return result


## Queue mode: starts the next strike needing allocation, finishing strikes
## that need none, and ends the queue when none are left.
func _advance_queue() -> void:
    while not _queue.is_empty():
        var result: CombatResult = _queue.pop_front()
        var unsaved := result.get_unsaved_wounds()
        if unsaved > 0 and result.target_squad.get_model_count() > 0:
            _pending = result
            _wounds_left = unsaved
            allocation_required.emit(result, _wounds_left)
            return
        result.wasted_wounds = unsaved
        _finish_strike(result)
    var results := _queued_all
    _queue_active = false
    _queued_all = []
    _wounds_left = 0
    var removed := []
    for result in results:
        var target := result.target_squad
        if target.is_destroyed() and target not in removed and _battle.get_squad(target.squad_id) == target:
            removed.append(target)
            _battle.remove_squad(target.squad_id)
    queue_resolved.emit(results)


func _finish_strike(outcome: CombatResult) -> void:
    outcome.models_remaining = outcome.target_squad.get_model_count()
    outcome.target_destroyed = outcome.target_squad.is_destroyed()
    strike_allocated.emit(outcome)


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
