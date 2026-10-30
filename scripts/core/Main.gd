extends Node
class_name Main
## Application coordinator: builds the battle state from the starting squad
## setups, wires the turn manager, squad view, selection and HUD together, and
## starts the game.

## Squads placed on the battlefield at the start of the game.
@export var squad_setups: Array[SquadSetup] = []

var battle := BattleState.new()

@onready var game_board: GameBoard = $GameBoard
@onready var squad_layer: SquadLayer = $GameBoard/Squads
@onready var turn_manager: TurnManager = $TurnManager
@onready var selection: SelectionManager = $SelectionManager
@onready var hud: HUD = $HUD


func _ready() -> void:
    for setup in squad_setups:
        battle.add_squad(SquadState.new(setup.squad, setup.start_position))
    squad_layer.bind_battle(battle)
    selection.bind_battle(battle)
    hud.bind_turn_manager(turn_manager)
    hud.bind_selection(selection)
    squad_layer.squad_clicked.connect(selection.select)
    squad_layer.empty_space_clicked.connect(selection.clear_selection)
    selection.selection_changed.connect(squad_layer.show_selection)
    turn_manager.start_game()
