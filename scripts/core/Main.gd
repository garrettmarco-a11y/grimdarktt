extends Node
class_name Main
## Application coordinator: builds the battle state from the starting squad
## setups, wires the turn manager, activation, squad view, selection, movement,
## shooting, assault, morale and HUD together, and starts the game.

## Squads placed on the battlefield at the start of the game.
@export var squad_setups: Array[SquadSetup] = []

var battle := BattleState.new()
## Shared by shooting and assault for the defender's casualty allocation.
var casualties := CasualtyAllocator.new()

@onready var game_board: GameBoard = $GameBoard
@onready var movement_overlay: MovementOverlay = $GameBoard/MovementOverlay
@onready var squad_layer: SquadLayer = $GameBoard/Squads
@onready var turn_manager: TurnManager = $TurnManager
@onready var selection: SelectionManager = $SelectionManager
@onready var movement: MovementController = $MovementController
@onready var activation: ActivationController = $ActivationController
@onready var shooting: ShootingController = $ShootingController
@onready var assault: AssaultController = $AssaultController
@onready var morale: MoraleController = $MoraleController
@onready var hud: HUD = $HUD


func _ready() -> void:
    for setup in squad_setups:
        battle.add_squad(SquadState.new(setup.squad, setup.start_position))
    squad_layer.bind_battle(battle)
    selection.bind_battle(battle)
    activation.bind(battle, turn_manager)
    movement.bind(battle, turn_manager, game_board.board_size)
    movement.activation = activation
    casualties.bind(activation, battle)
    shooting.bind(turn_manager, activation, battle, casualties)
    assault.bind(turn_manager, activation, battle, casualties)
    morale.bind(battle, turn_manager, activation, game_board.board_size)
    hud.bind_turn_manager(turn_manager)
    hud.bind_selection(selection)
    hud.bind_movement(movement)
    hud.bind_activation(activation, selection)
    hud.bind_shooting(shooting)
    hud.bind_casualties(casualties)
    hud.bind_assault(assault)
    hud.bind_morale(morale)
    squad_layer.squad_clicked.connect(selection.select)
    squad_layer.empty_space_clicked.connect(selection.clear_selection)
    squad_layer.destination_clicked.connect(_on_destination_clicked)
    squad_layer.squad_right_clicked.connect(_on_squad_right_clicked)
    selection.selection_changed.connect(squad_layer.show_selection)
    selection.selection_changed.connect(movement_overlay.show_squad)
    movement.move_rejected.connect(_on_move_rejected)
    turn_manager.phase_changed.connect(_on_phase_changed)
    activation.activation_changed.connect(_on_activation_changed)
    turn_manager.start_game()


func _on_destination_clicked(board_point: Vector2) -> void:
    movement.order_move(selection.selected_squad, board_point)


## A right-click on a squad targets it in the Shooting and Assault phases;
## otherwise it is a move destination, as before.
func _on_squad_right_clicked(target: SquadState, board_point: Vector2) -> void:
    match turn_manager.current_phase:
        TurnManager.Phase.SHOOTING:
            shooting.order_shot(activation.active_squad, target)
        TurnManager.Phase.ASSAULT:
            assault.order_assault(activation.active_squad, target)
        _:
            _on_destination_clicked(board_point)


func _on_move_rejected(_state: SquadState, destination: Vector2, _result: MovementRules.Result) -> void:
    movement_overlay.show_rejected(destination)


func _on_phase_changed(phase: TurnManager.Phase, _turn: int) -> void:
    movement_overlay.set_orders_enabled(phase == TurnManager.Phase.MOVEMENT)


func _on_activation_changed() -> void:
    squad_layer.show_activation(activation.active_squad, activation.get_activated_squads())
