extends RefCounted
class_name ObjectiveController
## Holds the authoritative objective score and game result. Scores every round
## at the end of the Consolidation phase (TurnManager.phase_ended, emitted
## before the next round can begin) with VictoryRules, and resolves the result
## when the TurnManager ends the game after the last round. Has no input or
## drawing code; the live battlefield display does not read these scores.

signal round_scored(score: VictoryRules.RoundScore)
signal game_finished(result: VictoryRules.GameResult)

## Accumulated VP per player, as of the last checkpoint.
var scores := VictoryRules.zero_scores()
## Every checkpoint so far, in round order.
var history: Array[VictoryRules.RoundScore] = []
## The final result once the game is over, else null.
var result: VictoryRules.GameResult

var _battle: BattleState
var _objectives: Array[ObjectiveSetup] = []


func bind(turn_manager: TurnManager, battle: BattleState, objectives: Array[ObjectiveSetup]) -> void:
    _battle = battle
    _objectives = objectives
    turn_manager.phase_ended.connect(_on_phase_ended)
    turn_manager.game_ended.connect(_on_game_ended)


## The most recent checkpoint, or null before the first.
func last_score() -> VictoryRules.RoundScore:
    return history.back() if not history.is_empty() else null


func _on_phase_ended(phase: TurnManager.Phase, turn: int) -> void:
    if phase != TurnManager.Phase.CONSOLIDATION:
        return
    if last_score() and last_score().round >= turn:
        push_error("ObjectiveController: round %d was already scored" % turn)
        return
    var score := VictoryRules.score_checkpoint(_objectives, _battle, turn, scores)
    scores = score.totals.duplicate()
    history.append(score)
    round_scored.emit(score)


func _on_game_ended(turn: int) -> void:
    result = VictoryRules.final_result(scores, turn)
    game_finished.emit(result)
