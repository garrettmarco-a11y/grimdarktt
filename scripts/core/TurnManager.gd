extends Node
class_name TurnManager
## Owns turn, phase, priority and squad-activation state. Has no UI dependencies.
##
## Flow:
##   start_game()                    -> turn 1, Movement, Player 1 holds priority
##   begin_phase(p1_count, p2_count) -> caller supplies eligible squad activations
##   start_activation() / end_activation(), repeated until both players reach 0
##   the phase then ends and the manager waits for the next begin_phase() call.
##
## Assumptions (approved by the project lead):
##   - A phase ends when both players have 0 remaining activations.
##   - Eligible activation counts are supplied by the caller at each phase start;
##     the manager does not decide which squads are eligible.
##   - Within a phase activations alternate, starting with the priority player;
##     a player with 0 remaining activations is skipped.

signal phase_changed(phase: Phase, turn: int)
signal phase_started(phase: Phase, turn: int, priority_player: int)
signal phase_ended(phase: Phase, turn: int)
signal turn_started(turn: int)
signal activation_started(player: int, phase: Phase)
signal activation_ended(player: int, phase: Phase)

enum Phase { MOVEMENT, SHOOTING, ASSAULT, MORALE }
enum State { NOT_STARTED, AWAITING_PHASE_START, IN_PHASE, ACTIVATION_IN_PROGRESS }

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


static func phase_to_string(phase: Phase) -> String:
    match phase:
        Phase.MOVEMENT:
            return "Movement"
        Phase.SHOOTING:
            return "Shooting"
        Phase.ASSAULT:
            return "Assault"
        Phase.MORALE:
            return "Morale"
    return "Unknown"


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


## Starts the current phase with each player's eligible squad activations.
## Priority goes to the player with more activations; a tie keeps the previous
## priority. If neither player has an activation, the phase ends immediately.
func begin_phase(player_one_activations: int, player_two_activations: int) -> bool:
    if state != State.AWAITING_PHASE_START:
        push_error("TurnManager.begin_phase: not awaiting a phase start")
        return false
    if player_one_activations < 0 or player_two_activations < 0:
        push_error("TurnManager.begin_phase: activation counts must be >= 0")
        return false

    _remaining[PLAYER_ONE] = player_one_activations
    _remaining[PLAYER_TWO] = player_two_activations
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


func get_remaining_activations(player: int) -> int:
    return _remaining.get(player, 0)


func _end_phase() -> void:
    var ended_phase := current_phase
    active_player = NO_PLAYER
    state = State.AWAITING_PHASE_START
    phase_ended.emit(ended_phase, turn_number)

    if ended_phase == Phase.MORALE:
        turn_number += 1
        current_phase = Phase.MOVEMENT
        turn_started.emit(turn_number)
    else:
        current_phase = (ended_phase + 1) as Phase
    phase_changed.emit(current_phase, turn_number)
