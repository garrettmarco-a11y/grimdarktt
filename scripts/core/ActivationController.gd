extends Node
class_name ActivationController
## Squad-level activation on top of TurnManager's player-level activation.
##
## TurnManager stays the authority for phase order, priority and which player
## is entitled to activate. This controller adds the squad identity it lacks:
## it supplies each phase's eligible squad counts to TurnManager, lets the
## entitled player activate one of their own eligible squads, and records which
## squads have activated this phase.
##
## Eligibility (approved by the project lead):
##   - Movement and Shooting: every squad on the battlefield.
##   - Morale: only squads that lost models since their last Morale
##     activation. A squad's loss flag clears when its Morale activation ends.
##   - Charge: squads that may declare a charge, decided by `charge_rule`
##     (see ChargeRules.can_declare_any). Eligibility can be lost mid-phase,
##     e.g. by being charged; withdraw() then removes the squad's waiting
##     activation.
##   - Procedure phases (Assault, Consolidation): no squad activates.
##   With no eligible squads an activation phase passes straight away.

signal activation_changed
## A squad's activation has just started; e.g. MoraleController runs mandatory
## tests here. Emitted after activation_changed.
signal squad_activated(state: SquadState)

enum Result { OK, NO_SQUAD, NOT_IN_PHASE, ACTIVATION_IN_PROGRESS, WRONG_PLAYER, ALREADY_ACTIVATED, NOT_ELIGIBLE }

## The squad currently activated, or null.
var active_squad: SquadState = null
## While true the active squad's activation cannot be ended by the player,
## e.g. while the defender allocates wounds from its shooting.
var locked := false:
    set(value):
        locked = value
        activation_changed.emit()

## Decides Charge-phase eligibility: Callable(state: SquadState) -> bool.
## No squad is eligible while it is unset.
var charge_rule := Callable()

var _battle: BattleState
var _turn_manager: TurnManager
## Squad ids that have completed an activation in the current phase.
var _activated: Dictionary = {}
## Squad ids whose waiting activation was withdrawn this phase.
var _withdrawn: Dictionary = {}
## Squad ids counted as eligible when the current phase began.
var _counted: Dictionary = {}


func bind(battle: BattleState, turn_manager: TurnManager) -> void:
    _battle = battle
    _turn_manager = turn_manager
    battle.squad_removed.connect(_on_squad_removed)
    turn_manager.phase_changed.connect(_on_phase_changed)
    turn_manager.activation_ended.connect(_on_turn_manager_activation_ended)


static func is_eligible(state: SquadState, phase: TurnManager.Phase) -> bool:
    if phase == TurnManager.Phase.MORALE:
        return state.lost_models_since_morale
    if phase == TurnManager.Phase.CHARGE:
        return false  # Charge eligibility needs battle context: see is_squad_eligible.
    return true


## Whether `state` may activate in `phase`, including the Charge rule.
func is_squad_eligible(state: SquadState, phase: TurnManager.Phase) -> bool:
    if _turn_manager and _turn_manager.is_procedure(phase):
        return false
    if phase == TurnManager.Phase.CHARGE:
        return charge_rule.is_valid() and charge_rule.call(state) and not _withdrawn.has(state.squad_id)
    return is_eligible(state, phase)


## Removes the waiting activation of `state`, which has just become ineligible
## in the current phase (e.g. it was charged before it could declare). Does
## nothing if it has activated, is activating, or was already withdrawn.
func withdraw(state: SquadState) -> bool:
    if state == null or has_activated(state) or is_active_squad(state) or _withdrawn.has(state.squad_id):
        return false
    if _turn_manager.state != TurnManager.State.IN_PHASE and _turn_manager.state != TurnManager.State.ACTIVATION_IN_PROGRESS:
        return false
    if not _counted.has(state.squad_id):
        return false
    _withdrawn[state.squad_id] = true
    _turn_manager.remove_squad_activation(state.get_player())
    activation_changed.emit()
    return true


## The player entitled to activate next (or activating now), or NO_PLAYER.
func get_active_player() -> int:
    return _turn_manager.active_player if _turn_manager else TurnManager.NO_PLAYER


func get_phase() -> TurnManager.Phase:
    return _turn_manager.current_phase


func is_active_squad(state: SquadState) -> bool:
    return state != null and state == active_squad


func has_activated(state: SquadState) -> bool:
    return state != null and _activated.has(state.squad_id)


func get_activated_squads() -> Array[SquadState]:
    var squads: Array[SquadState] = []
    for state in _battle.get_squads():
        if _activated.has(state.squad_id):
            squads.append(state)
    return squads


## Whether `state` may be activated now. Changes nothing.
func can_activate(state: SquadState) -> Result:
    if state == null:
        return Result.NO_SQUAD
    if _turn_manager.state == TurnManager.State.ACTIVATION_IN_PROGRESS:
        return Result.ACTIVATION_IN_PROGRESS
    if _turn_manager.state != TurnManager.State.IN_PHASE:
        return Result.NOT_IN_PHASE
    if has_activated(state):
        return Result.ALREADY_ACTIVATED
    if state.get_player() != _turn_manager.active_player:
        return Result.WRONG_PLAYER
    if not is_squad_eligible(state, _turn_manager.current_phase):
        return Result.NOT_ELIGIBLE
    return Result.OK


func activate(state: SquadState) -> Result:
    var result := can_activate(state)
    if result != Result.OK:
        return result
    active_squad = state
    _turn_manager.start_activation()
    activation_changed.emit()
    squad_activated.emit(state)
    return result


## Completes the active squad's activation; play passes per TurnManager.
func end_activation() -> bool:
    if active_squad == null:
        push_error("ActivationController.end_activation: no squad is activated")
        return false
    if locked:
        return false
    var ended := _turn_manager.end_activation()
    # TurnManager emits activation_ended before choosing the next player, so
    # report the change only once the hand-over is complete.
    activation_changed.emit()
    return ended


func _on_turn_manager_activation_ended(_player: int, phase: TurnManager.Phase) -> void:
    if active_squad:
        _activated[active_squad.squad_id] = true
        if phase == TurnManager.Phase.MORALE:
            active_squad.clear_morale_losses()
        active_squad = null


func _on_phase_changed(phase: TurnManager.Phase, _turn: int) -> void:
    _activated.clear()
    _withdrawn.clear()
    _counted.clear()
    active_squad = null
    if _turn_manager.is_procedure(phase):
        # Procedure phases run their own procedure (TurnManager); no squad
        # activates in them.
        activation_changed.emit()
        return
    if _battle.get_squads().is_empty():
        # Nothing can ever activate; starting phases would cycle forever.
        activation_changed.emit()
        return
    var counts := {TurnManager.PLAYER_ONE: 0, TurnManager.PLAYER_TWO: 0}
    for state in _battle.get_squads():
        if is_squad_eligible(state, phase) and counts.has(state.get_player()):
            counts[state.get_player()] += 1
            _counted[state.squad_id] = true
    activation_changed.emit()
    # May end the phase at once (e.g. Morale with no tests), which re-enters here.
    _turn_manager.begin_phase(counts[TurnManager.PLAYER_ONE], counts[TurnManager.PLAYER_TWO])
    activation_changed.emit()


func _on_squad_removed(state: SquadState) -> void:
    if is_active_squad(state):
        end_activation()
    elif not has_activated(state) and _counted.has(state.squad_id) and not _withdrawn.has(state.squad_id) \
            and (_turn_manager.state == TurnManager.State.IN_PHASE
                or _turn_manager.state == TurnManager.State.ACTIVATION_IN_PROGRESS):
        _turn_manager.remove_squad_activation(state.get_player())
    activation_changed.emit()
