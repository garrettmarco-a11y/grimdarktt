extends Node
class_name Main
## Application coordinator: wires the turn manager, squad selection and HUD
## together and starts the game.

@onready var game_board: GameBoard = $GameBoard
@onready var squad_layer: SquadLayer = $GameBoard/Squads
@onready var turn_manager: TurnManager = $TurnManager
@onready var selection: SelectionManager = $SelectionManager
@onready var hud: HUD = $HUD


func _ready() -> void:
    hud.bind_turn_manager(turn_manager)
    hud.bind_selection(selection)
    squad_layer.squad_clicked.connect(selection.select)
    squad_layer.empty_space_clicked.connect(selection.clear_selection)
    selection.selection_changed.connect(squad_layer.show_selection)
    turn_manager.start_game()
