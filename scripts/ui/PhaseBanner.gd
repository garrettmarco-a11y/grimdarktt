extends Control
class_name PhaseBanner
## Minimal labels showing the current turn and phase, and the objective score
## as of the last scoring checkpoint (never live control).

@onready var label: Label = $Label
@onready var score_label: Label = $ScoreLabel


func show_phase(phase: TurnManager.Phase, turn: int) -> void:
    label.text = "Turn %d - %s" % [turn, TurnManager.phase_to_string(phase)]


func show_game_over(turn: int) -> void:
    label.text = "Turn %d - Game over" % turn


## The score before any checkpoint.
func show_initial_score(round_limit: int) -> void:
    score_label.text = "VP  Player 1: 0  -  Player 2: 0   (%d rounds)" % round_limit


## The accumulated score after checkpoint `score`.
func show_score(score: VictoryRules.RoundScore, round_limit: int) -> void:
    score_label.text = "VP after round %d/%d  Player 1: %d  -  Player 2: %d" % [score.round, round_limit,
        score.totals[TurnManager.PLAYER_ONE], score.totals[TurnManager.PLAYER_TWO]]


func show_result(result: VictoryRules.GameResult) -> void:
    score_label.text = "Final after %d rounds: %s" % [result.rounds, HUD.format_result(result)]
