extends CanvasLayer
class_name HUD
## Displays game state. Reads from the turn manager, selection, activation,
## movement, shooting, charge, engagement, consolidation and morale controllers
## and the casualty allocator through signals only.

@onready var phase_banner: PhaseBanner = $PhaseBanner
@onready var squad_info_panel: SquadInfoPanel = $SquadInfoPanel
@onready var order_feedback: Label = $OrderFeedback
@onready var activation_panel: ActivationPanel = $ActivationPanel
@onready var allocation_panel: AllocationPanel = $AllocationPanel

var _movement: MovementController
## Assault-phase target declarations; created when engagements are bound.
var target_panel: TargetPanel


func bind_turn_manager(turn_manager: TurnManager) -> void:
    turn_manager.phase_changed.connect(phase_banner.show_phase)


func bind_selection(selection: SelectionManager) -> void:
    selection.selection_changed.connect(squad_info_panel.show_squad)


func bind_activation(activation: ActivationController, selection: SelectionManager) -> void:
    activation_panel.bind(activation, selection)


## Terrain for the info panel's cover line.
func bind_terrain(terrain: TerrainMap) -> void:
    squad_info_panel.terrain = terrain


func bind_movement(movement: MovementController) -> void:
    _movement = movement
    movement.move_ordered.connect(_on_move_ordered)
    movement.move_rejected.connect(_on_move_rejected)


func bind_shooting(shooting: ShootingController) -> void:
    shooting.shot_rejected.connect(_on_shot_rejected)


func bind_morale(morale: MoraleController) -> void:
    morale.morale_tested.connect(_on_morale_tested)
    morale.regrouped.connect(_on_regrouped)
    activation_panel.bind_morale(morale)


func _on_morale_tested(result: MoraleResult) -> void:
    order_feedback.modulate = Color.WHITE if result.passed else Color(1.0, 0.65, 0.4)
    order_feedback.text = format_morale_result(result)


func _on_regrouped(state: SquadState) -> void:
    order_feedback.modulate = Color.WHITE
    order_feedback.text = "%s regroups: Shaken removed, half movement, no shooting or charging this turn" \
        % state.data.display_name


## Results from shooting and assault both arrive through the shared allocator.
func bind_casualties(allocator: CasualtyAllocator) -> void:
    allocator.allocation_required.connect(_on_allocation_required)
    allocator.resolved.connect(_on_attack_resolved)
    allocation_panel.bind(allocator)


func bind_charge(charge: ChargeController) -> void:
    charge.charge_resolved.connect(_on_charge_resolved)
    charge.charge_rejected.connect(_on_charge_rejected)


func _on_charge_resolved(result: ChargeResult) -> void:
    order_feedback.modulate = Color.WHITE
    order_feedback.text = format_charge_result(result)


static func format_charge_result(result: ChargeResult) -> String:
    var lines := PackedStringArray()
    lines.append("%s charges %s" % [result.charger.data.display_name, result.target.data.display_name])
    lines.append("Rolled %d: up to %s" % [result.roll, String.num(result.distance, 1)])
    if result.succeeded:
        lines.append("Contact: %d model%s engaged" % [result.models_in_contact, "" if result.models_in_contact == 1 else "s"])
    else:
        lines.append("Failed: no contact, moved as far as the roll allowed")
    return "\n".join(lines)


func _on_charge_rejected(_charger: SquadState, target: SquadState, result: ChargeRules.Result) -> void:
    order_feedback.modulate = Color(1.0, 0.45, 0.4)
    match result:
        ChargeRules.Result.NO_SQUAD:
            order_feedback.text = "Activate a squad to charge"
        ChargeRules.Result.NO_TARGET:
            order_feedback.text = "Choose an enemy squad to charge"
        ChargeRules.Result.WRONG_PHASE:
            order_feedback.text = "Charges only in the Charge phase"
        ChargeRules.Result.NOT_ACTIVATED:
            order_feedback.text = "Activate the squad before charging"
        ChargeRules.Result.OWN_SQUAD:
            order_feedback.text = "Cannot charge your own squad"
        ChargeRules.Result.MORALE_RESTRICTED:
            order_feedback.text = "Morale: this squad cannot charge"
        ChargeRules.Result.ALREADY_ENGAGED:
            order_feedback.text = "Already engaged this round"
        ChargeRules.Result.TARGET_UNAVAILABLE:
            order_feedback.text = "That squad cannot be charged"
        ChargeRules.Result.OUT_OF_RANGE:
            order_feedback.text = "%s is beyond the maximum charge distance" % target.data.display_name


func bind_engagements(controller: EngagementController) -> void:
    target_panel = TargetPanel.new()
    target_panel.name = "TargetPanel"
    add_child(target_panel)
    target_panel.bind(controller)
    controller.engagement_started.connect(_on_engagement_started)
    controller.target_declaration_required.connect(_on_target_declaration_required)
    controller.strikes_rolled.connect(_on_strikes_rolled)
    controller.engagement_resolved.connect(_on_engagement_resolved)


func _on_engagement_started(_engagement: EngagementTracker.Engagement, squads: Array) -> void:
    order_feedback.modulate = Color.WHITE
    order_feedback.text = "Engagement: %s" % ", ".join(squads.map(func(s): return s.data.display_name))


func _on_target_declaration_required(squad: SquadState, _options: Array) -> void:
    order_feedback.modulate = Color.WHITE
    order_feedback.text = "Player %d: choose %s's target (right-click or the panel)" % [squad.get_player(), squad.data.display_name]


func _on_strikes_rolled(_engagement: EngagementTracker.Engagement, results: Array[CombatResult]) -> void:
    order_feedback.modulate = Color.WHITE
    order_feedback.text = format_strikes(results)


func _on_engagement_resolved(outcome: EngagementOutcome) -> void:
    order_feedback.modulate = Color.WHITE
    order_feedback.text = format_engagement_outcome(outcome)


func bind_consolidation(controller: ConsolidationController) -> void:
    controller.consolidated.connect(_on_consolidated)


## Adds the consolidation summary under the last engagement result; says
## nothing when no squad consolidated.
func _on_consolidated(entries: Array) -> void:
    if entries.is_empty():
        return
    order_feedback.modulate = Color.WHITE
    order_feedback.text = (order_feedback.text + "\n" if order_feedback.text != "" else "") + format_consolidation(entries)


static func format_consolidation(entries: Array) -> String:
    var lines := PackedStringArray(["Consolidation:"])
    for entry in entries:
        lines.append("%s -> %s: %d moved, %d held" % [entry.squad.data.display_name, entry.target.data.display_name,
            entry.moved, entry.held])
    return "\n".join(lines)


## The side-wide result of an engagement and the losers' tests.
static func format_engagement_outcome(outcome: EngagementOutcome) -> String:
    var lines := PackedStringArray(["Engagement result:"])
    for player in [TurnManager.PLAYER_ONE, TurnManager.PLAYER_TWO]:
        var enemy := TurnManager.other_player(player)
        var bonus: int = outcome.outnumbering[player]
        lines.append("Player %d: %d enemy lost%s = %d (%d left)" % [player, outcome.models_lost[enemy],
            " +%d outnumbering" % bonus if bonus > 0 else "", outcome.scores[player], outcome.survivors[player]])
    match outcome.reason:
        EngagementOutcome.Reason.BOTH_DESTROYED:
            lines.append("Both sides destroyed: draw")
        EngagementOutcome.Reason.SIDE_DESTROYED:
            lines.append("Player %d wins: the other side is destroyed" % outcome.winner)
        _:
            lines.append("Draw: nobody tests" if outcome.is_draw() else "Player %d wins" % outcome.winner)
    for test in outcome.loss_tests:
        lines.append(format_morale_result(test).replace("\n", "; "))
    return "\n".join(lines)


## One line per strike of an engagement, all rolled before any casualty.
static func format_strikes(results: Array) -> String:
    var lines := PackedStringArray(["Strikes (all rolled before casualties):"])
    for result in results:
        lines.append("%s -> %s: %d fight, %d attacks, %d hit, %d unsaved" % [result.attacker_squad.data.display_name,
            result.target_squad.data.display_name, result.get_eligible_count(), result.get_total_attacks(),
            result.get_hits(), result.get_unsaved_wounds()])
    if results.is_empty():
        lines.append("No squad could strike")
    return "\n".join(lines)


## Shows why the battle could not start.
func show_setup_error(message: String) -> void:
    order_feedback.modulate = Color(1.0, 0.45, 0.4)
    order_feedback.text = message


func _on_move_ordered(state: SquadState, _from: Vector2, _to: Vector2) -> void:
    order_feedback.modulate = Color.WHITE
    order_feedback.text = "%s moving (%.1f left)" % [state.data.display_name, state.get_remaining_movement()]
    var plan := _movement.last_plan if _movement else null
    if plan and not plan.fell_short.is_empty():
        order_feedback.text += "; %d model%s could not reach formation" % [plan.fell_short.size(),
            "" if plan.fell_short.size() == 1 else "s"]
    if not CohesionRules.is_coherent(state):
        order_feedback.text += "; %s" % CohesionRules.describe(state).to_lower()


func _on_move_rejected(state: SquadState, destination: Vector2, result: MovementRules.Result) -> void:
    order_feedback.modulate = Color(1.0, 0.45, 0.4)
    match result:
        MovementRules.Result.NO_SQUAD:
            order_feedback.text = "Select a squad to move"
        MovementRules.Result.WRONG_PHASE:
            order_feedback.text = "Move orders only in the Movement phase"
        MovementRules.Result.NOT_ACTIVATED:
            order_feedback.text = "Activate %s before moving it" % state.data.display_name
        MovementRules.Result.MOVEMENT_COMPLETE:
            order_feedback.text = "%s has finished moving" % state.data.display_name
        MovementRules.Result.OFF_BOARD:
            order_feedback.text = "Destination is off the battlefield"
        MovementRules.Result.OUT_OF_RANGE:
            var cost := _movement.order_cost(state, destination) if _movement \
                else MovementRules.distance(state.board_position, destination)
            order_feedback.text = "Out of range: %.1f > %.1f left" % [cost, state.get_remaining_movement()]
        MovementRules.Result.IMPASSABLE:
            order_feedback.text = "Path blocked by impassable terrain"
        MovementRules.Result.BLOCKED_BY_MODEL:
            order_feedback.text = "Path blocked by another squad's model"


func _on_attack_resolved(result: CombatResult) -> void:
    order_feedback.modulate = Color.WHITE
    order_feedback.text = format_combat_result(result)


func _on_shot_rejected(_firing: SquadState, target: SquadState, result: ShootingRules.OrderResult) -> void:
    order_feedback.modulate = Color(1.0, 0.45, 0.4)
    match result:
        ShootingRules.OrderResult.NO_SQUAD:
            order_feedback.text = "Activate a squad to shoot"
        ShootingRules.OrderResult.NO_TARGET:
            order_feedback.text = "Choose a target squad"
        ShootingRules.OrderResult.WRONG_PHASE:
            order_feedback.text = "Shooting only in the Shooting phase"
        ShootingRules.OrderResult.NOT_ACTIVATED:
            order_feedback.text = "Activate the squad before shooting"
        ShootingRules.OrderResult.OWN_SQUAD:
            order_feedback.text = "Cannot shoot your own squad"
        ShootingRules.OrderResult.ALLOCATION_PENDING:
            order_feedback.text = "Allocate the pending wounds first"
        ShootingRules.OrderResult.MORALE_RESTRICTED:
            order_feedback.text = "Morale: this squad cannot shoot this turn"
        ShootingRules.OrderResult.NO_VISIBLE_TARGET:
            order_feedback.text = "No model can see that squad"
        ShootingRules.OrderResult.ENGAGED_TARGET:
            order_feedback.text = "%s is engaged in combat: it cannot be shot at" % target.data.display_name


func _on_allocation_required(result: CombatResult, _wounds_left: int) -> void:
    order_feedback.modulate = Color.WHITE
    order_feedback.text = format_combat_result(result)


static func format_combat_result(result: CombatResult) -> String:
    var lines := PackedStringArray()
    var melee := result.attack_type == CombatResult.AttackType.MELEE
    lines.append("%s %s %s" % [result.attacker_squad.data.display_name, "assaulted" if melee else "shot",
        result.target_squad.data.display_name])
    lines.append("Target: %s cover, armour %s; hits on %d+" % [TerrainPiece.cover_name(result.target_cover),
        "%d+" % result.target_armor_save if result.target_armor_save > 0 else "none", result.hit_target])
    lines.append("%s: %d  Unable: %d" % ["Fought" if melee else "Fired", result.get_eligible_count(),
        result.get_ineligible_count()])
    lines.append("Attacks %d: %d hit, %d miss" % [result.get_total_attacks(), result.get_hits(), result.get_misses()])
    lines.append("Wounds %d: %d saved, %d unsaved" % [result.get_wounds(), result.get_saves(), result.get_unsaved_wounds()])
    if result.get_eligible_count() == 0:
        lines.append("No model could %s" % ("fight" if melee else "fire"))
    for model in result.model_results:
        if not model.is_eligible():
            lines.append("%s: %s" % [model.model_name, eligibility_text(model.eligibility)])
        elif model.hits == 0:
            lines.append("%s: %d/%d hit" % [model.model_name, model.hits, model.rolls.size()])
        else:
            lines.append("%s: %d/%d hit, %d wnd (%d+), %d saved (%s)" % [model.model_name, model.hits,
                model.rolls.size(), model.wounds, model.wound_target, model.saves, save_text(model.save_target)])
    var casualties := result.get_casualties()
    lines.append("Casualties: %s" % (", ".join(casualties) if not casualties.is_empty() else "none"))
    var target := result.target_squad.data.display_name
    if result.target_destroyed:
        lines.append("%s destroyed" % target)
    elif result.get_unsaved_wounds() > result.allocations.size():
        lines.append("%s: allocating wounds" % target)
    else:
        lines.append("%s: %d models left" % [target, result.models_remaining])
    return "\n".join(lines)


static func format_morale_result(result: MoraleResult) -> String:
    var lines := PackedStringArray()
    var kind: String = ["morale test", "rally test", "assault-loss test"][result.kind]
    var ld := "Ld %d" % result.leadership
    if result.below_half:
        ld += " (%d, -1 below half)" % result.base_leadership
    lines.append("%s %s: %d+%d=%d vs %s" % [result.squad.data.display_name, kind, result.dice[0],
        result.dice[1], result.total, ld])
    match result.kind:
        MoraleResult.Kind.ORDINARY:
            lines.append("Passed" if result.passed else "Failed: Shaken")
        MoraleResult.Kind.RALLY:
            lines.append("Rallied: half movement, no shooting or charging this turn" if result.passed \
                else "Failed: still Broken, no shooting or charging this turn")
        MoraleResult.Kind.ASSAULT_LOSS:
            lines.append("Passed: holds" if result.passed else "Failed: Broken")
    if result.fell_back:
        var edge := MoraleRules.edge_name(result.fallback_edge)
        if result.removed:
            lines.append("Fell back off the %s edge: removed" % edge)
        else:
            lines.append("Fell back %.1f towards the %s edge" % [result.fallback_from.distance_to(result.fallback_to), edge])
    return "\n".join(lines)


static func save_text(target: int) -> String:
    if target <= 0:
        return "no save"
    if not DamageRules.can_be_saved(target):
        return "%d+, unsavable" % target
    return "%d+" % target


static func eligibility_text(eligibility: int) -> String:
    match eligibility:
        CombatResult.Eligibility.NO_RANGED_WEAPON:
            return "no ranged weapon"
        CombatResult.Eligibility.OUT_OF_RANGE:
            return "out of range"
        CombatResult.Eligibility.NO_LINE_OF_SIGHT:
            return "no line of sight"
        CombatResult.Eligibility.NO_MELEE_WEAPON:
            return "no melee weapon"
        CombatResult.Eligibility.NOT_ENGAGED:
            return "not engaged"
    return "can fire"
