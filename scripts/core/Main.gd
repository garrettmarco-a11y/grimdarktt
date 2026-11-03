extends Node
class_name Main
## Application coordinator: builds the battle state from the starting squad
## setups, wires the turn manager, activation, squad view, selection, movement,
## shooting, charges, engagements, consolidation, morale and HUD together, and
## starts the game.

## Squads placed on the battlefield at the start of the game.
@export var squad_setups: Array[SquadSetup] = []
## Terrain placed on the battlefield; static for the battle.
@export var terrain_setups: Array[TerrainSetup] = []

var battle := BattleState.new()
var terrain: TerrainMap
## Why the starting squad layout was rejected; empty if it is legal.
var layout_errors := PackedStringArray()
## Shared by shooting and assault for the defender's casualty allocation.
var casualties := CasualtyAllocator.new()
## Round-long engagement commitments, reset at the start of every round.
var engagements := EngagementTracker.new()
## Charge-phase declarations and charge movement.
var charge := ChargeController.new()
## The Assault-phase engagement procedure.
var engagement := EngagementController.new()
## The automatic Consolidation-phase procedure.
var consolidation := ConsolidationController.new()

@onready var game_board: GameBoard = $GameBoard
@onready var terrain_layer: TerrainLayer = $GameBoard/TerrainLayer
@onready var movement_overlay: MovementOverlay = $GameBoard/MovementOverlay
@onready var squad_layer: SquadLayer = $GameBoard/Squads
@onready var turn_manager: TurnManager = $TurnManager
@onready var selection: SelectionManager = $SelectionManager
@onready var movement: MovementController = $MovementController
@onready var activation: ActivationController = $ActivationController
@onready var shooting: ShootingController = $ShootingController
@onready var morale: MoraleController = $MoraleController
@onready var hud: HUD = $HUD


func _ready() -> void:
    # An invalid configuration (overlapping footprints) is reported by
    # TerrainMap and leaves the battlefield without terrain.
    terrain = TerrainMap.new(terrain_setups)
    terrain_layer.bind(terrain)
    # Starting positions are validated before the battle begins; an invalid
    # layout is rejected whole, never rearranged, and the game does not start.
    var squads: Array[SquadState] = []
    for setup in squad_setups:
        squads.append(SquadState.new(setup.squad, setup.start_position))
    layout_errors = ModelPlacement.layout_errors(squads, game_board.board_size, terrain)
    for error in layout_errors:
        push_error("Invalid starting layout: %s" % error)
    if layout_errors.is_empty():
        for state in squads:
            battle.add_squad(state)
    squad_layer.bind_battle(battle)
    selection.bind_battle(battle)
    activation.bind(battle, turn_manager)
    movement.bind(battle, turn_manager, game_board.board_size)
    movement.activation = activation
    movement.terrain = terrain
    casualties.bind(activation, battle)
    shooting.bind(turn_manager, activation, battle, casualties)
    shooting.set_terrain(terrain)
    morale.bind(battle, turn_manager, activation, game_board.board_size)
    morale.terrain = terrain
    engagements.bind(turn_manager)
    charge.name = "ChargeController"
    add_child(charge)
    charge.bind(turn_manager, activation, battle, engagements, game_board.board_size)
    charge.terrain = terrain
    engagement.name = "EngagementController"
    add_child(engagement)
    engagement.bind(turn_manager, battle, engagements, casualties)
    engagement.terrain = terrain
    engagement.morale = morale
    consolidation.name = "ConsolidationController"
    add_child(consolidation)
    consolidation.bind(turn_manager, battle, engagements, engagement, game_board.board_size)
    consolidation.terrain = terrain
    hud.bind_turn_manager(turn_manager)
    hud.bind_terrain(terrain)
    hud.bind_selection(selection)
    hud.bind_movement(movement)
    hud.bind_activation(activation, selection)
    hud.bind_shooting(shooting)
    hud.bind_casualties(casualties)
    hud.bind_morale(morale)
    hud.bind_charge(charge)
    hud.bind_engagements(engagement)
    hud.bind_consolidation(consolidation)
    squad_layer.squad_clicked.connect(selection.select)
    squad_layer.empty_space_clicked.connect(selection.clear_selection)
    squad_layer.destination_clicked.connect(_on_destination_clicked)
    squad_layer.squad_right_clicked.connect(_on_squad_right_clicked)
    selection.selection_changed.connect(squad_layer.show_selection)
    selection.selection_changed.connect(movement_overlay.show_squad)
    movement.move_rejected.connect(_on_move_rejected)
    turn_manager.phase_changed.connect(_on_phase_changed)
    activation.activation_changed.connect(_on_activation_changed)
    if layout_errors.is_empty():
        turn_manager.start_game()
    else:
        hud.show_setup_error("Invalid starting layout: %s" % layout_errors[0])


func _on_destination_clicked(board_point: Vector2) -> void:
    if turn_manager.current_phase in [TurnManager.Phase.CHARGE, TurnManager.Phase.ASSAULT]:
        return  # charges and target declarations name an enemy squad, not a point
    movement.order_move(selection.selected_squad, board_point)


## A right-click on a squad targets it in the Shooting and Assault phases;
## otherwise it is a move destination, as before.
func _on_squad_right_clicked(target: SquadState, board_point: Vector2) -> void:
    match turn_manager.current_phase:
        TurnManager.Phase.SHOOTING:
            shooting.order_shot(activation.active_squad, target)
        TurnManager.Phase.CHARGE:
            charge.declare_charge(activation.active_squad, target)
        TurnManager.Phase.ASSAULT:
            # A right-click names the declaring squad's target.
            engagement.declare_target(engagement.get_declaring_squad(), target)
        _:
            _on_destination_clicked(board_point)


func _on_move_rejected(_state: SquadState, destination: Vector2, _result: MovementRules.Result) -> void:
    movement_overlay.show_rejected(destination)


func _on_phase_changed(phase: TurnManager.Phase, _turn: int) -> void:
    movement_overlay.set_orders_enabled(phase == TurnManager.Phase.MOVEMENT)


func _on_activation_changed() -> void:
    squad_layer.show_activation(activation.active_squad, activation.get_activated_squads())
