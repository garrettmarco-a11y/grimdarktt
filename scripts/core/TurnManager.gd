extends Node
class_name TurnManager
## Owns turn, phase, priority and squad-activation state. Has no UI dependencies.
##
## Each game round (turn) runs six phases in order: Movement, Shooting, Morale,
## Charge, Assault, Consolidation. The turn ends after Consolidation.
##
## Activation phases (Movement, Shooting, Morale, Charge):
##   begin_phase(p1_count, p2_count) -> caller supplies eligible squad activations
##   start_activation() / end_activation(), repeated until both players reach 0
##   the phase then ends and the manager waits for the next begin_phase() call.
##
## Procedure phases (see PROCEDURE_PHASES) are not squad activations: on
## entering one the manager starts the procedure registered for it
## (register_procedure) and the phase lasts until that procedure calls
## complete_procedure_phase(). A procedure phase with nothing registered has
## nothing to do and ends at once. begin_phase() is refused in a procedure
## phase, and complete_procedure_phase() is refused anywhere else, so neither
## kind of phase can end the other early.
##
## Rules (approved by the project lead):
##   - Priority is set once per game turn, at the start of the Movement phase:
##     the player with more activations gets it, a tie keeps the previous
##     priority. It then holds for Shooting, Assault and Morale.
##   - Eligible activation counts are supplied by the caller at each phase start;
##     the manager does not decide which squads are eligible.
##   - Within every phase, Morale included, activations alternate starting with
##     the priority player; a player with 0 remaining activations is skipped.
##   - A squad lost mid-phase is removed with remove_squad_activation(). The
##     squad currently activating is never removed this way; its activation
##     simply ends with end_activation().
##   - A phase ends when both players have 0 remaining activations.

signal phase_changed(phase: Phase, turn: int)
signal phase_started(phase: Phase, turn: int, priority_player: int)
signal phase_ended(phase: Phase, turn: int)
signal turn_started(turn: int)
signal activation_started(player: int, phase: Phase)
signal activation_ended(player: int, phase: Phase)

enum Phase { MOVEMENT, SHOOTING, MORALE, CHARGE, ASSAULT, CONSOLIDATION }
enum State { NOT_STARTED, AWAITING_PHASE_START, IN_PHASE, ACTIVATION_IN_PROGRESS, PROCEDURE_IN_PROGRESS }

## Phases resolved by a procedure rather than by squad activations.
const PROCEDURE_PHASES: Array[Phase] = [Phase.ASSAULT, Phase.CONSOLIDATION]
## The last phase of a game round.
const LAST_PHASE := Phase.CONSOLIDATION

const NO_PLAYER := 0
const PLAYER_ONE := 1
const PLAYER_TWO := 2

var current_phase: Phase = Phase.MOVEMENT
var turn_number: int = 0
var priority_player: int = PLAYER_ONE
## Player whose squad acts next (or is acting now); NO_PLAYER outside a phase.
var active_player: int = NO_PLAYER
var state: State = State.NOT_STARTED

var _remaining := {PLAYER_ONE: 0, PLAYER_TWO: 0}
## Phase -> Callable started when that procedure phase begins.
var _procedures := {}


static func phase_to_string(phase: Phase) -> String:
    match phase:
        Phase.MOVEMENT:
            return "Movement"
        Phase.SHOOTING:
            return "Shooting"
        Phase.MORALE:
            return "Morale"
        Phase.CHARGE:
            return "Charge"
        Phase.ASSAULT:
            return "Assault"
        Phase.CONSOLIDATION:
            return "Consolidation"
    return "Unknown"


static func is_procedure_phase(phase: Phase) -> bool:
    return phase in PROCEDURE_PHASES


## True if `phase` is a procedure phase (same as is_procedure_phase).
func is_procedure(phase: Phase) -> bool:
    return is_procedure_phase(phase)


## Registers `procedure` to run whenever procedure phase `phase` begins. It
## receives no arguments and must eventually call complete_procedure_phase().
func register_procedure(phase: Phase, procedure: Callable) -> void:
    if not is_procedure_phase(phase):
        push_error("TurnManager.register_procedure: %s is not a procedure phase" % phase_to_string(phase))
        return
    _procedures[phase] = procedure


## Ends procedure phase `phase` once its procedure has finished. Refused unless
## that procedure phase is the one in progress.
func complete_procedure_phase(phase: Phase) -> bool:
    if state != State.PROCEDURE_IN_PROGRESS or current_phase != phase:
        push_error("TurnManager.complete_procedure_phase: %s is not in progress" % phase_to_string(phase))
        return false
    _end_phase()
    return true


static func other_player(player: int) -> int:
    return PLAYER_TWO if player == PLAYER_ONE else PLAYER_ONE


func start_game() -> void:
    turn_number = 1
    current_phase = Phase.MOVEMENT
    priority_player = PLAYER_ONE
    active_player = NO_PLAYER
    _remaining = {PLAYER_ONE: 0, PLAYER_TWO: 0}
    state = State.AWAITING_PHASE_START
    turn_started.emit(turn_number)
    phase_changed.emit(current_phase, turn_number)
    _begin_procedure_if_any()


## Starts the current phase with each player's eligible squad activations.
## In the Movement phase, priority goes to the player with more activations and a
## tie keeps the previous priority; later phases keep that turn's priority.
## If neither player has an activation, the phase ends immediately.
func begin_phase(player_one_activations: int, player_two_activations: int) -> bool:
    if state != State.AWAITING_PHASE_START:
        push_error("TurnManager.begin_phase: not awaiting a phase start")
        return false
    if is_procedure(current_phase):
        push_error("TurnManager.begin_phase: %s is a procedure phase" % phase_to_string(current_phase))
        return false
    if player_one_activations < 0 or player_two_activations < 0:
        push_error("TurnManager.begin_phase: activation counts must be >= 0")
        return false

    _remaining[PLAYER_ONE] = player_one_activations
    _remaining[PLAYER_TWO] = player_two_activations
    if current_phase == Phase.MOVEMENT:
        if player_one_activations > player_two_activations:
            priority_player = PLAYER_ONE
        elif player_two_activations > player_one_activations:
            priority_player = PLAYER_TWO

    state = State.IN_PHASE
    phase_started.emit(current_phase, turn_number, priority_player)

    if _remaining[priority_player] > 0:
        active_player = priority_player
    elif _remaining[other_player(priority_player)] > 0:
        active_player = other_player(priority_player)
    else:
        _end_phase()
    return true


## Starts one squad activation for `active_player`. Returns the player, or
## NO_PLAYER if no activation can start.
func start_activation() -> int:
    if state != State.IN_PHASE:
        push_error("TurnManager.start_activation: no phase awaiting an activation")
        return NO_PLAYER
    state = State.ACTIVATION_IN_PROGRESS
    activation_started.emit(active_player, current_phase)
    return active_player


## Completes the current squad activation and hands play to the next player.
func end_activation() -> bool:
    if state != State.ACTIVATION_IN_PROGRESS:
        push_error("TurnManager.end_activation: no activation in progress")
        return false
    var player := active_player
    _remaining[player] -= 1
    state = State.IN_PHASE
    activation_ended.emit(player, current_phase)

    var opponent := other_player(player)
    if _remaining[opponent] > 0:
        active_player = opponent
    elif _remaining[player] > 0:
        active_player = player
    else:
        _end_phase()
    return true


## Removes one not-yet-activated squad of `player` from the current phase, e.g.
## when it is destroyed. If the player due to act runs out, play passes to the
## opponent; if both run out, the phase ends.
func remove_squad_activation(player: int) -> bool:
    if state != State.IN_PHASE and state != State.ACTIVATION_IN_PROGRESS:
        push_error("TurnManager.remove_squad_activation: no phase in progress")
        return false
    if player != PLAYER_ONE and player != PLAYER_TWO:
        push_error("TurnManager.remove_squad_activation: unknown player %d" % player)
        return false
    var waiting: int = _remaining[player]
    if state == State.ACTIVATION_IN_PROGRESS and player == active_player:
        waiting -= 1
    if waiting <= 0:
        push_error("TurnManager.remove_squad_activation: player %d has no waiting squad" % player)
        return false
    _remaining[player] -= 1

    # Mid-activation, end_activation() picks the next player from the new counts.
    if state == State.IN_PHASE and _remaining[active_player] == 0:
        var opponent := other_player(active_player)
        if _remaining[opponent] > 0:
            active_player = opponent
        else:
            _end_phase()
    return true


func get_remaining_activations(player: int) -> int:
    return _remaining.get(player, 0)


func _end_phase() -> void:
    var ended_phase := current_phase
    active_player = NO_PLAYER
    state = State.AWAITING_PHASE_START
    phase_ended.emit(ended_phase, turn_number)

    if ended_phase == LAST_PHASE:
        turn_number += 1
        current_phase = Phase.MOVEMENT
        turn_started.emit(turn_number)
    else:
        current_phase = (ended_phase + 1) as Phase
    phase_changed.emit(current_phase, turn_number)
    _begin_procedure_if_any()


## Enters the current phase's procedure if it is a procedure phase whose start
## nobody has already handled.
func _begin_procedure_if_any() -> void:
    if not is_procedure(current_phase) or state != State.AWAITING_PHASE_START:
        return
    var phase := current_phase
    var turn := turn_number
    state = State.PROCEDURE_IN_PROGRESS
    active_player = NO_PLAYER
    phase_started.emit(phase, turn, priority_player)
    var procedure: Callable = _procedures.get(phase, Callable())
    if procedure.is_valid():
        procedure.call()
    elif state == State.PROCEDURE_IN_PROGRESS and current_phase == phase and turn_number == turn:
        _end_phase()
