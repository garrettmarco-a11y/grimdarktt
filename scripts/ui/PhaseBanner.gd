extends Control
class_name PhaseBanner
## Minimal label showing the current turn and phase.

@onready var label: Label = $Label


func show_phase(phase: TurnManager.Phase, turn: int) -> void:
    label.text = "Turn %d - %s" % [turn, TurnManager.phase_to_string(phase)]
