extends Node
class_name MoraleController
## Applies morale: mandatory tests when squads activate, consolidation, Broken
## rally tests, forced fall-back, and assault-loss tests. Rules come from
## MoraleRules; state changes go to SquadState, removals through BattleState,
## and activations end through the ActivationController. Has no input or
## drawing code.
##
##   - Morale phase: a squad flagged with losses takes one ordinary test when
##     activated (failure: Shaken; a Broken squad skips it), then its
##     activation ends by itself, clearing the flag as before.
##   - A Broken squad tests to rally at its first activation of each turn. A
##     pass clears Broken and allows half movement; a fail falls back its full
##     Movement and ends the activation. Either way it may not shoot or initiate
##     an assault for the rest of the turn.
##   - A Shaken squad may consolidate during its Movement activation: Shaken
##     clears, movement is capped at half, and it may not shoot or initiate an
##     assault for the rest of the turn.

signal morale_tested(result: MoraleResult)
signal consolidated(state: SquadState)

enum ConsolidateResult { OK, NO_SQUAD, NOT_ACTIVATED, WRONG_PHASE, NOT_SHAKEN }

var dice := DiceRoller.new()
## Battlefield size in board units, for fall-back.
var board_size := Vector2.ZERO

var _battle: BattleState
var _turn_manager: TurnManager
var _activation: ActivationController


func bind(battle: BattleState, turn_manager: TurnManager, activation: ActivationController,
        board_units: Vector2) -> void:
    _battle = battle
    _turn_manager = turn_manager
    _activation = activation
    board_size = board_units
    turn_manager.turn_started.connect(_on_turn_started)
    activation.squad_activated.connect(_on_squad_activated)


## Whether `state` may consolidate now. Changes nothing.
func can_consolidate(state: SquadState) -> ConsolidateResult:
    if state == null:
        return ConsolidateResult.NO_SQUAD
    if not _activation.is_active_squad(state):
        return ConsolidateResult.NOT_ACTIVATED
    if _turn_manager.current_phase != TurnManager.Phase.MOVEMENT:
        return ConsolidateResult.WRONG_PHASE
    if state.morale_status != SquadState.MoraleStatus.SHAKEN:
        return ConsolidateResult.NOT_SHAKEN
    return ConsolidateResult.OK


## The active Shaken squad consolidates: Shaken clears, movement is capped at
## half its normal Movement, and it may not shoot or initiate an assault for the
## rest of the turn. The activation stays open for the move.
func consolidate(state: SquadState) -> ConsolidateResult:
    var result := can_consolidate(state)
    if result != ConsolidateResult.OK:
        return result
    state.morale_status = SquadState.MoraleStatus.STEADY
    state.morale_restricted_this_turn = true
    state.limit_movement_allowance(MovementRules.allowance_for(state.data) * 0.5)
    consolidated.emit(state)
    return result


## The losing squad of an assault tests; on a failure it becomes Broken and
## falls back. Combat scoring that picks the loser is not implemented yet.
## A squad broken mid-turn first tries to rally at its first activation of the
## next turn, and may not shoot or initiate an assault for the rest of this one.
func resolve_assault_loss(state: SquadState) -> MoraleResult:
    var result := _test(state, MoraleResult.Kind.ASSAULT_LOSS)
    if not result.passed:
        state.morale_status = SquadState.MoraleStatus.BROKEN
        state.rally_attempted_this_turn = true
        state.morale_restricted_this_turn = true
        result.status_after = state.morale_status
        _fall_back(state, result)
    morale_tested.emit(result)
    return result


func _on_turn_started(_turn: int) -> void:
    for state in _battle.get_squads():
        state.morale_restricted_this_turn = false
        state.rally_attempted_this_turn = false


func _on_squad_activated(state: SquadState) -> void:
    if state.morale_status == SquadState.MoraleStatus.BROKEN and not state.rally_attempted_this_turn:
        _rally(state)
    elif _turn_manager.current_phase == TurnManager.Phase.MORALE:
        _ordinary_test(state)


func _ordinary_test(state: SquadState) -> void:
    if state.morale_status != SquadState.MoraleStatus.BROKEN:
        var result := _test(state, MoraleResult.Kind.ORDINARY)
        if not result.passed:
            state.morale_status = SquadState.MoraleStatus.SHAKEN
            result.status_after = state.morale_status
        morale_tested.emit(result)
    _activation.end_activation()


func _rally(state: SquadState) -> void:
    state.rally_attempted_this_turn = true
    state.morale_restricted_this_turn = true
    var result := _test(state, MoraleResult.Kind.RALLY)
    if result.passed:
        state.morale_status = SquadState.MoraleStatus.STEADY
        result.status_after = state.morale_status
        state.limit_movement_allowance(MovementRules.allowance_for(state.data) * 0.5)
        morale_tested.emit(result)
        return
    _fall_back(state, result)
    morale_tested.emit(result)
    if not result.removed and _activation.is_active_squad(state):
        _activation.end_activation()


## Moves the squad's anchor its full normal Movement towards the nearest edge,
## bypassing voluntary movement validation; off the battlefield it is removed.
func _fall_back(state: SquadState, result: MoraleResult) -> void:
    var distance := MovementRules.allowance_for(state.data)
    result.fell_back = true
    result.fallback_from = state.board_position
    result.fallback_edge = MoraleRules.nearest_edge(state.board_position, board_size)
    result.fallback_to = MoraleRules.fallback_destination(state.board_position, board_size, distance)
    if MoraleRules.is_off_board(result.fallback_to, board_size):
        result.removed = true
        state.remove_all_models()
        _battle.remove_squad(state.squad_id)
    else:
        state.apply_move(result.fallback_to, true)


func _test(state: SquadState, kind: MoraleResult.Kind) -> MoraleResult:
    var result := MoraleResult.new()
    result.squad = state
    result.kind = kind
    result.status_before = state.morale_status
    result.status_after = state.morale_status
    result.base_leadership = MoraleRules.base_leadership(state)
    result.below_half = state.is_below_half_strength()
    result.leadership = MoraleRules.effective_leadership(state)
    result.dice = MoraleRules.roll_2d6(dice)
    result.total = result.dice[0] + result.dice[1]
    result.passed = MoraleRules.passes(result.total, result.leadership)
    return result
