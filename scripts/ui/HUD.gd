extends CanvasLayer
class_name HUD
## Displays game state. Reads from the turn manager through signals only.

@onready var phase_banner: PhaseBanner = $PhaseBanner


func bind_turn_manager(turn_manager: TurnManager) -> void:
    turn_manager.phase_changed.connect(phase_banner.show_phase)
