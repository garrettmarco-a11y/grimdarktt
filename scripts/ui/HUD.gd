extends CanvasLayer
class_name HUD
## Displays game state. Reads from the turn manager and selection through signals only.

@onready var phase_banner: PhaseBanner = $PhaseBanner
@onready var squad_info_panel: SquadInfoPanel = $SquadInfoPanel


func bind_turn_manager(turn_manager: TurnManager) -> void:
    turn_manager.phase_changed.connect(phase_banner.show_phase)


func bind_selection(selection: SelectionManager) -> void:
    selection.selection_changed.connect(squad_info_panel.show_squad)
