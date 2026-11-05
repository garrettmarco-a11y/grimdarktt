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
##   - The round is Movement, Shooting, Morale, Charge (alternating squad
##     activations), then Assault and Consolidation (procedure phases). The
##     turn ends after Consolidation.
##   - Priority is set once per game turn, at the start of the Movement phase:
##     the player with more activations gets it, a tie keeps the previous
##     priority. It then holds for every later phase of the turn (procedures
##     use it too, e.g. to order Assault declarations).
##   - Eligible activation counts are supplied by the caller at each phase start;
##     the manager does not decide which squads are eligible.
##   - Within every activation phase (Movement, Shooting, Morale, Charge),
##     activations alternate starting with the priority player; a player with
##     0 remaining activations is skipped.
##   - A squad lost mid-phase is removed with remove_squad_activation(). The
##     squad currently activating is never removed this way; its activation
##     simply ends with end_activation().
##   - A phase ends when both players have 0 remaining activations.
##   - Phases that need no input end at once, so several can pass in one call.
##     At most one new round starts within such a chain: a further round's
##     start is deferred to the next frame, so a stretch of rounds in which
##     nobody can act (e.g. every squad locked in combat with no wound landing)
##     never piles up on the call stack.
##   - The game lasts `round_limit` rounds (0: no limit). The last round's
##     Consolidation ends as usual, phase_ended is emitted (round-end scoring
##     listens to it), and then the game is over: state GAME_OVER, game_ended
##     is emitted, and no further round, phase or activation can begin.

signal phase_changed(phase: Phase, turn: int)
signal phase_started(phase: Phase, turn: int, priority_player: int)
signal phase_ended(phase: Phase, turn: int)
signal turn_started(turn: int)
signal activation_started(player: int, phase: Phase)
signal activation_ended(player: int, phase: Phase)
## The game is over: `turn`, the last round, has ended (after its phase_ended).
signal game_ended(turn: int)

enum Phase { MOVEMENT, SHOOTING, MORALE, CHARGE, ASSAULT, CONSOLIDATION }
enum State { NOT_STARTED, AWAITING_PHASE_START, IN_PHASE, ACTIVATION_IN_PROGRESS, PROCEDURE_IN_PROGRESS, GAME_OVER }

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
## Rounds the game lasts; the game ends after the last one's Consolidation.
## 0 means no limit. Set by the scenario before start_game().
var round_limit := 0

var _remaining := {PLAYER_ONE: 0, PLAYER_TWO: 0}
## Phase -> Callable started when that procedure phase begins.
var _procedures := {}
## Nesting of _end_phase calls, and rounds begun within the current chain.
var _chain_depth := 0
var _rounds_in_chain := 0


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


## Procedure phases with no registered procedure. Such a phase would end at
## once with nothing done: acceptable in isolated tests, an error in the game
## (see Main.required_procedure_errors).
func missing_procedures() -> Array[Phase]:
    var missing: Array[Phase] = []
    for phase in PROCEDURE_PHASES:
        if not _procedures.has(phase):
            missing.append(phase)
    return missing


## Ends procedure phase `phase` once its procedure has finished. Refused unless
## that procedure phase is the one in progress.
func complete_procedure_phase(phase: Phase) -> bool:
    if state != State.PROCEDURE_IN_PROGRESS or current_phase != phase:
        push_error("TurnManager.complete_procedure_phase: %s is not in progress" % phase_to_string(phase))
        return false
    _end_phase()
    return true


func is_game_over() -> bool:
    return state == State.GAME_OVER


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
    _begin_procedure_if_any(Phase.MOVEMENT, turn_number)


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
    _chain_depth += 1
    var ended_phase := current_phase
    active_player = NO_PLAYER
    state = State.AWAITING_PHASE_START
    phase_ended.emit(ended_phase, turn_number)

    if ended_phase == LAST_PHASE and round_limit > 0 and turn_number >= round_limit:
        # The last round is over (its round-end scoring ran in phase_ended).
        state = State.GAME_OVER
        game_ended.emit(turn_number)
    elif ended_phase == LAST_PHASE and _rounds_in_chain >= 1:
        # A round already began in this chain: start the next one on the next
        # frame. (Not call_deferred: a deferred call queued while deferred
        # calls are being flushed runs in the same flush.)
        var tree := Engine.get_main_loop() as SceneTree
        if tree and not tree.process_frame.is_connected(_start_next_round):
            tree.process_frame.connect(_start_next_round, CONNECT_ONE_SHOT)
    elif ended_phase == LAST_PHASE:
        _rounds_in_chain += 1
        _begin_round()
    else:
        current_phase = (ended_phase + 1) as Phase
        var entered := current_phase
        var turn := turn_number
        phase_changed.emit(current_phase, turn_number)
        _begin_procedure_if_any(entered, turn)
    _chain_depth -= 1
    if _chain_depth == 0:
        _rounds_in_chain = 0


func _start_next_round() -> void:
    if state != State.AWAITING_PHASE_START or current_phase != LAST_PHASE:
        return
    _chain_depth += 1
    _rounds_in_chain += 1
    _begin_round()
    _chain_depth -= 1
    if _chain_depth == 0:
        _rounds_in_chain = 0


func _begin_round() -> void:
    turn_number += 1
    current_phase = Phase.MOVEMENT
    var turn := turn_number
    turn_started.emit(turn_number)
    phase_changed.emit(current_phase, turn_number)
    _begin_procedure_if_any(Phase.MOVEMENT, turn)


## Enters the procedure of `phase` (just entered in `turn`) if it is a
## procedure phase whose start nobody has already handled. A caller resuming
## after a nested chain of phase changes passes the phase it entered, so it
## never starts a later phase's procedure by mistake.
func _begin_procedure_if_any(phase: Phase, turn: int) -> void:
    if current_phase != phase or turn_number != turn:
        return
    if not is_procedure(current_phase) or state != State.AWAITING_PHASE_START:
        return
    state = State.PROCEDURE_IN_PROGRESS
    active_player = NO_PLAYER
    phase_started.emit(phase, turn, priority_player)
    var procedure: Callable = _procedures.get(phase, Callable())
    if procedure.is_valid():
        procedure.call()
    elif state == State.PROCEDURE_IN_PROGRESS and current_phase == phase and turn_number == turn:
        _end_phase()
