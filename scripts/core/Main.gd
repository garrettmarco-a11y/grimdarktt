extends Node
class_name Main
## Application coordinator: wires the turn manager to the HUD and starts the game.

@onready var game_board: GameBoard = $GameBoard
@onready var turn_manager: TurnManager = $TurnManager
@onready var hud: HUD = $HUD


func _ready() -> void:
    hud.bind_turn_manager(turn_manager)
    turn_manager.start_game()
