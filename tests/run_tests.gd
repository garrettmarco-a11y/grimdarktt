extends SceneTree
## Native headless test runner (no external framework).
##
## Run from the project root:
##   godot --headless --path . --import
##   godot --headless --path . -s res://tests/run_tests.gd
##
## Every method whose name starts with "test_" is run. The process exits with
## code 0 when all checks pass and 1 when any check fails.

const P1 := TurnManager.PLAYER_ONE
const P2 := TurnManager.PLAYER_TWO
const Phase := TurnManager.Phase

var _failures: Array[String] = []


## Dice that return a fixed sequence of rolls, for deterministic tests.
## Running out of scripted rolls fails the current test.
class ScriptedDice extends DiceRoller:
    static var exhausted_count := 0
    var rolls: Array[int] = []

    func _init(values: Array[int]) -> void:
        rolls = values.duplicate()

    func roll_d6() -> int:
        if rolls.is_empty():
            exhausted_count += 1
            push_error("ScriptedDice: no scripted rolls left")
            return 1
        return rolls.pop_front()


func _initialize() -> void:
    _run_all.call_deferred()


func _run_all() -> void:
    var failed_tests := 0
    var test_count := 0
    for method in get_method_list():
        var method_name: String = method["name"]
        if not method_name.begins_with("test_"):
            continue
        test_count += 1
        var failures_before := _failures.size()
        var exhausted_before := ScriptedDice.exhausted_count
        await call(method_name)
        if ScriptedDice.exhausted_count != exhausted_before:
            _failures.append("ScriptedDice ran out of scripted rolls")
        if _failures.size() == failures_before:
            print("PASS  %s" % method_name)
        else:
            failed_tests += 1
            print("FAIL  %s" % method_name)
            for i in range(failures_before, _failures.size()):
                print("        %s" % _failures[i])

    print("")
    print("%d tests, %d failed" % [test_count, failed_tests])
    quit(1 if failed_tests > 0 or test_count == 0 else 0)


func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
    if actual != expected:
        _failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])


func _new_game() -> TurnManager:
    var tm := TurnManager.new()
    tm.start_game()
    return tm


## Begins the current phase and completes every activation. Returns acting players in order.
func _play_phase(tm: TurnManager, p1_count: int, p2_count: int) -> Array:
    var actors := []
    tm.begin_phase(p1_count, p2_count)
    while tm.state == TurnManager.State.IN_PHASE:
        if actors.size() > p1_count + p2_count:
            _failures.append("_play_phase: phase did not end after %d activations" % actors.size())
            break
        actors.append(tm.start_activation())
        tm.end_activation()
    return actors



## Plays out the rest of the current game turn with one activation each.
func _finish_turn(tm: TurnManager) -> void:
    var turn := tm.turn_number
    while tm.turn_number == turn:
        _play_phase(tm, 1, 1)


func test_initial_state() -> void:
    var tm := _new_game()
    _check_eq(tm.current_phase, Phase.MOVEMENT, "initial phase")
    _check_eq(tm.turn_number, 1, "initial turn")
    _check_eq(tm.priority_player, P1, "initial priority")
    _check_eq(tm.state, TurnManager.State.AWAITING_PHASE_START, "initial state")
    tm.free()


func test_phase_order() -> void:
    var tm := _new_game()
    var changes := []
    tm.phase_changed.connect(func(phase, turn): changes.append([phase, turn]))
    for i in 4:
        _play_phase(tm, 1, 1)
    _check_eq(changes, [
        [Phase.SHOOTING, 1], [Phase.ASSAULT, 1], [Phase.MORALE, 1], [Phase.MOVEMENT, 2],
    ], "phase_changed sequence")
    tm.free()


func test_alternating_activation() -> void:
    var tm := _new_game()
    _check_eq(_play_phase(tm, 3, 3), [P1, P2, P1, P2, P1, P2], "actors with 3 vs 3")
    tm.free()


func test_priority_to_player_with_more_activations() -> void:
    var tm := _new_game()
    var started := []
    tm.phase_started.connect(func(_phase, _turn, priority): started.append(priority))
    _check_eq(_play_phase(tm, 2, 3), [P2, P1, P2, P1, P2], "actors with 2 vs 3")
    _check_eq(started, [P2], "priority reported by phase_started")
    tm.free()


func test_priority_set_at_turn_start_and_held_for_turn() -> void:
    var tm := _new_game()
    _check_eq(_play_phase(tm, 1, 3), [P2, P1, P2, P2], "Movement 1 vs 3")
    _check_eq(_play_phase(tm, 3, 1), [P2, P1, P1, P1], "Shooting keeps Player 2 priority")
    _check_eq(_play_phase(tm, 4, 2), [P2, P1, P2, P1, P1, P1], "Assault keeps Player 2 priority")
    _check_eq(_play_phase(tm, 2, 0), [P1, P1], "Morale: priority holder with no tests is skipped")
    _check_eq(tm.priority_player, P2, "priority held through Morale")
    _check_eq(tm.turn_number, 2, "turn advanced")
    _check_eq(_play_phase(tm, 3, 1), [P1, P2, P1, P1], "next turn's Movement recalculates")
    _check_eq(tm.priority_player, P1, "priority after next turn's Movement")
    tm.free()


func test_tie_retains_previous_priority() -> void:
    var tm := _new_game()
    _play_phase(tm, 2, 2)
    _check_eq(tm.priority_player, P1, "tie at game start keeps Player 1")
    _finish_turn(tm)
    _play_phase(tm, 1, 2)
    _check_eq(tm.priority_player, P2, "Player 2 gains priority with more activations")
    _finish_turn(tm)
    _check_eq(_play_phase(tm, 2, 2), [P2, P1, P2, P1], "tie keeps Player 2 acting first")
    _check_eq(tm.priority_player, P2, "priority after tie")
    tm.free()


func test_skips_player_with_no_remaining_activations() -> void:
    var tm := _new_game()
    _check_eq(_play_phase(tm, 0, 2), [P2, P2], "Player 1 has none")
    _check_eq(_play_phase(tm, 1, 3), [P2, P1, P2, P2], "Player 1 runs out mid-phase")
    tm.free()


func test_empty_phase_ends_immediately() -> void:
    var tm := _new_game()
    _check_eq(_play_phase(tm, 0, 0), [], "no activations")
    _check_eq(tm.current_phase, Phase.SHOOTING, "phase advanced")
    _check_eq(tm.priority_player, P1, "0 vs 0 is a tie")
    tm.free()


func test_turn_advances_after_morale() -> void:
    var tm := _new_game()
    var turns := []
    tm.turn_started.connect(func(turn): turns.append(turn))
    for i in 3:
        _play_phase(tm, 1, 2)
    _check_eq(tm.current_phase, Phase.MORALE, "phase before morale completes")
    _check_eq(tm.turn_number, 1, "turn before morale completes")
    _play_phase(tm, 1, 0)
    _check_eq(tm.current_phase, Phase.MOVEMENT, "phase after morale")
    _check_eq(tm.turn_number, 2, "turn after morale")
    _check_eq(turns, [2], "turn_started emissions")
    tm.free()


func test_activation_is_per_squad_and_guarded() -> void:
    var tm := _new_game()
    var events := []
    tm.activation_started.connect(func(player, phase): events.append(["start", player, phase]))
    tm.activation_ended.connect(func(player, phase): events.append(["end", player, phase]))
    tm.begin_phase(2, 1)
    _check_eq(tm.start_activation(), P1, "first activation")
    _check_eq(tm.get_remaining_activations(P1), 2, "count unchanged until activation ends")
    tm.end_activation()
    _check_eq(tm.get_remaining_activations(P1), 1, "one squad activation consumed")
    _check_eq(events, [["start", P1, Phase.MOVEMENT], ["end", P1, Phase.MOVEMENT]], "activation signals")
    print("        (the next 3 errors are expected)")
    _check(not tm.end_activation(), "end_activation without a started activation is rejected")
    tm.start_activation()
    _check_eq(tm.start_activation(), TurnManager.NO_PLAYER, "second concurrent activation rejected")
    _check(not tm.begin_phase(1, 1), "begin_phase rejected mid-phase")
    tm.free()


func test_remove_waiting_squad_from_other_player() -> void:
    var tm := _new_game()
    tm.begin_phase(2, 2)
    _check(tm.remove_squad_activation(P2), "removal accepted")
    _check_eq(tm.get_remaining_activations(P2), 1, "count reduced immediately")
    var actors := []
    while tm.state == TurnManager.State.IN_PHASE:
        actors.append(tm.start_activation())
        tm.end_activation()
    _check_eq(actors, [P1, P2, P1], "play continues with reduced count")
    tm.free()


func test_removal_passes_play_when_next_player_runs_out() -> void:
    var tm := _new_game()
    tm.begin_phase(1, 1)
    _check(tm.remove_squad_activation(P1), "removal accepted")
    _check_eq(tm.active_player, P2, "play passes to Player 2")
    tm.free()


func test_removal_ends_phase_when_both_run_out() -> void:
    var tm := _new_game()
    var ended := []
    tm.phase_ended.connect(func(phase, _turn): ended.append(phase))
    tm.begin_phase(1, 1)
    tm.start_activation()
    tm.end_activation()
    _check(tm.remove_squad_activation(P2), "removal accepted")
    _check_eq(ended, [Phase.MOVEMENT], "phase ended")
    _check_eq(tm.current_phase, Phase.SHOOTING, "next phase reached")
    tm.free()


func test_removal_during_activation() -> void:
    var tm := _new_game()
    tm.begin_phase(2, 1)
    tm.start_activation()
    _check(tm.remove_squad_activation(P2), "opponent's waiting squad removed mid-activation")
    _check(tm.remove_squad_activation(P1), "own waiting squad removed mid-activation")
    _check_eq(tm.active_player, P1, "acting squad's activation still in progress")
    print("        (the next 2 errors are expected)")
    _check(not tm.remove_squad_activation(P1), "acting squad cannot be removed")
    _check(not tm.remove_squad_activation(P2), "player with no squads left cannot lose one")
    tm.end_activation()
    _check_eq(tm.current_phase, Phase.SHOOTING, "phase ends with the acting squad's activation")
    tm.free()


func test_board_rect_follows_size_and_scale() -> void:
    var board := GameBoard.new()
    # Temporary test fixture values, not the battlefield's final dimensions.
    board.board_size = Vector2(10.0, 8.0)
    board.pixels_per_unit = 5.0
    _check_eq(board.get_board_rect(), Rect2(0.0, 0.0, 50.0, 40.0), "board rect")
    _check_eq(board.units_to_pixels(Vector2(2.0, 3.5)), Vector2(10.0, 17.5), "units to pixels")
    _check_eq(board.pixels_to_units(Vector2(10.0, 17.5)), Vector2(2.0, 3.5), "pixels to units")
    board.free()


func test_board_contains_point_is_continuous() -> void:
    var board := GameBoard.new()
    board.board_size = Vector2(10.0, 8.0)
    _check(board.contains_point(Vector2(3.37, 7.91)), "off-grid interior point")
    _check(board.contains_point(Vector2.ZERO), "corner is on the board")
    _check(board.contains_point(Vector2(10.0, 8.0)), "far corner is on the board")
    _check(not board.contains_point(Vector2(-0.01, 4.0)), "left of the edge")
    _check(not board.contains_point(Vector2(5.0, 8.01)), "below the edge")
    board.free()


func test_grid_line_positions() -> void:
    _check_eq(GameBoard.grid_line_positions(6.0, 24.0), PackedFloat32Array([6.0, 12.0, 18.0]), "edges excluded")
    _check_eq(GameBoard.grid_line_positions(5.0, 12.0), PackedFloat32Array([5.0, 10.0]), "uneven length")
    _check_eq(GameBoard.grid_line_positions(0.5, 1.5), PackedFloat32Array([0.5, 1.0]), "fractional step")
    _check_eq(GameBoard.grid_line_positions(0.0, 10.0).size(), 0, "zero step draws nothing")


func test_board_layout_in_main_scene() -> void:
    var main: Node = load("res://scenes/core/Main.tscn").instantiate()
    root.add_child(main)
    await process_frame
    var board := main.get_node("GameBoard") as GameBoard
    var banner := main.get_node("HUD/PhaseBanner") as Control
    var board_rect := board.get_global_transform() * board.get_board_rect()
    var viewport := Rect2(Vector2.ZERO, Vector2(
        ProjectSettings.get_setting("display/window/size/viewport_width"),
        ProjectSettings.get_setting("display/window/size/viewport_height")))
    _check_eq(viewport.size, Vector2(1280, 720), "viewport size unchanged")
    _check(viewport.encloses(board_rect), "board %s fits the viewport" % board_rect)
    _check(not board_rect.intersects(banner.get_global_rect()), "board clears the phase banner")
    main.queue_free()
    await process_frame


func _load_main() -> Node:
    var main: Node = load("res://scenes/core/Main.tscn").instantiate()
    root.add_child(main)
    await process_frame
    return main


func _make_state(squad_id: StringName, player: int, position := Vector2.ZERO) -> SquadState:
    # Temporary test fixture values, not game balance data.
    var squad := SquadData.new()
    squad.squad_id = squad_id
    squad.display_name = String(squad_id)
    squad.player = player
    squad.profile = UnitProfile.new()
    return SquadState.new(squad, position)


## Sends a left click at `position` in viewport coordinates. In-local-coords input
## avoids the headless window's tiny size rescaling the click.
func _click(position: Vector2) -> void:
    var click := InputEventMouseButton.new()
    click.button_index = MOUSE_BUTTON_LEFT
    click.position = position
    click.global_position = position
    click.pressed = true
    root.push_input(click, true)
    var release := click.duplicate() as InputEventMouseButton
    release.pressed = false
    root.push_input(release, true)


## Sends a right click at `position` in viewport coordinates.
func _right_click(position: Vector2) -> void:
    var click := InputEventMouseButton.new()
    click.button_index = MOUSE_BUTTON_RIGHT
    click.position = position
    click.global_position = position
    click.pressed = true
    root.push_input(click, true)
    var release := click.duplicate() as InputEventMouseButton
    release.pressed = false
    root.push_input(release, true)


func test_placeholder_squads_have_identity_and_stats() -> void:
    var main: Node = await _load_main()
    var squads: Array[SquadState] = main.battle.get_squads()
    _check_eq(squads.size(), 2, "placeholder squad count")
    var ids := {}
    for state in squads:
        var squad := state.data
        _check(squad != null, "%s has squad data" % state.squad_id)
        if squad == null:
            continue
        ids[state.squad_id] = true
        _check(state.squad_id != &"", "squad has an id")
        _check(squad.display_name != "", "%s has a name" % state.squad_id)
        _check(squad.profile != null, "%s has a profile" % state.squad_id)
        if squad.profile:
            var p := squad.profile
            _check(p.movement > 0.0 and p.quality > 0 and p.toughness > 0 and p.wounds > 0 and p.leadership > 0,
                "%s has positive placeholder stats" % state.squad_id)
    _check_eq(ids.size(), squads.size(), "squad ids are unique")
    _check_eq(main.get_node("GameBoard/Squads").get_tokens().size(), squads.size(), "one token per squad")
    main.queue_free()
    await process_frame


func test_placeholder_squads_player_affiliation() -> void:
    var main: Node = await _load_main()
    var p1_squad: SquadState = main.battle.get_squad(&"p1_line_squad")
    var p2_squad: SquadState = main.battle.get_squad(&"p2_raider_squad")
    _check(p1_squad != null and p2_squad != null, "both placeholder squads found by id")
    if p1_squad and p2_squad:
        _check_eq(p1_squad.get_player(), P1, "Line Squad belongs to Player 1")
        _check_eq(p2_squad.get_player(), P2, "Raider Squad belongs to Player 2")
        var layer: SquadLayer = main.get_node("GameBoard/Squads")
        _check_eq(layer.get_token(&"p1_line_squad").get_player(), P1, "Line Squad token drawn for Player 1")
        _check(SquadToken.PLAYER_COLORS[P1] != SquadToken.PLAYER_COLORS[P2], "players drawn in different colours")
    main.queue_free()
    await process_frame


func test_squad_state_references_data_and_keeps_identity() -> void:
    var squad: SquadData = load("res://data/squads/p1_line_squad.tres")
    var state := SquadState.new(squad, Vector2(3.0, 4.0))
    _check_eq(state.data, squad, "state references its SquadData")
    _check_eq(state.squad_id, &"p1_line_squad", "id taken from data")
    _check_eq(state.get_player(), P1, "player read from data")
    state.board_position = Vector2(9.5, 1.25)
    _check_eq(state.squad_id, &"p1_line_squad", "id unchanged after moving")
    print("        (the next 2 errors are expected)")
    state.squad_id = &"renamed"
    state.data = SquadData.new()
    _check_eq(state.squad_id, &"p1_line_squad", "id cannot be reassigned")
    _check_eq(state.data, squad, "data cannot be reassigned")


func test_squad_state_owns_position() -> void:
    var state := _make_state(&"alpha", P1, Vector2(2.0, 3.0))
    _check_eq(state.board_position, Vector2(2.0, 3.0), "start position stored in state")
    var moves := []
    state.position_changed.connect(func(s): moves.append(s.board_position))
    state.board_position = Vector2(7.25, 3.5)
    state.board_position = Vector2(7.25, 3.5)
    _check_eq(moves, [Vector2(7.25, 3.5)], "position_changed emitted once per actual change")


func test_battle_state_add_and_remove() -> void:
    var battle := BattleState.new()
    var alpha := _make_state(&"alpha", P1)
    var bravo := _make_state(&"bravo", P2)
    var removed := []
    battle.squad_removed.connect(func(s): removed.append(s))
    _check(battle.add_squad(alpha) and battle.add_squad(bravo), "squads added")
    _check_eq(battle.get_squads(), [alpha, bravo], "squads in insertion order")
    _check_eq(battle.get_squad(&"bravo"), bravo, "lookup by id")
    print("        (the next 2 errors are expected)")
    _check(not battle.add_squad(_make_state(&"alpha", P2)), "duplicate id rejected")
    _check(not battle.remove_squad(&"missing"), "unknown id rejected")
    _check(battle.remove_squad(&"alpha"), "squad removed")
    _check_eq(removed, [alpha], "squad_removed reported")
    _check_eq(battle.get_squad(&"alpha"), null, "removed squad gone")


func test_tokens_follow_squad_state_position() -> void:
    var main: Node = await _load_main()
    var board: GameBoard = main.get_node("GameBoard")
    var layer: SquadLayer = main.get_node("GameBoard/Squads")
    for state in main.battle.get_squads():
        var token := layer.get_token(state.squad_id)
        _check_eq(token.state, state, "%s token draws its state" % state.squad_id)
        _check_eq(token.position, board.units_to_pixels(state.board_position), "%s start pixel position" % state.squad_id)
        _check(board.contains_point(state.board_position), "%s is on the board" % state.squad_id)
        _check_eq(layer.token_at(token.position), token, "%s is hit at its centre" % state.squad_id)
    _check_eq(layer.token_at(Vector2(-50.0, -50.0)), null, "no squad off the board")

    var squad: SquadState = main.battle.get_squad(&"p1_line_squad")
    var token := layer.get_token(&"p1_line_squad")
    var old_pixels := token.position
    squad.board_position = Vector2(20.5, 7.75)
    var new_pixels := board.units_to_pixels(Vector2(20.5, 7.75))
    _check_eq(token.target_position, new_pixels, "token targets the new state position")
    _check_eq(token.position, old_pixels, "token animates rather than jumping")
    token.advance(100.0)
    _check_eq(token.position, new_pixels, "token arrives at the state position")
    _check_eq(layer.token_at(token.position), token, "token clickable at its new position")
    _check(not "board_position" in token, "token keeps no board position of its own")
    token.position = Vector2.ZERO
    _check_eq(squad.board_position, Vector2(20.5, 7.75), "moving the token does not change the state")
    main.queue_free()
    await process_frame


func test_layer_follows_battle_additions_and_removals() -> void:
    var main: Node = await _load_main()
    var layer: SquadLayer = main.get_node("GameBoard/Squads")
    var extra := _make_state(&"extra", P2, Vector2(24.0, 24.0))
    main.battle.add_squad(extra)
    _check(layer.get_token(&"extra") != null, "token created for an added squad")
    _check_eq(layer.get_tokens().size(), 3, "three tokens")
    main.battle.remove_squad(&"extra")
    _check_eq(layer.get_token(&"extra"), null, "token removed with its squad")
    _check_eq(layer.get_tokens().size(), 2, "two tokens")
    extra.board_position = Vector2(1.0, 1.0)
    main.queue_free()
    await process_frame


func test_select_updates_selection() -> void:
    var selection := SelectionManager.new()
    var alpha := _make_state(&"alpha", P1)
    var changes := []
    selection.selection_changed.connect(func(s): changes.append(s))
    _check_eq(selection.selected_squad, null, "nothing selected initially")
    selection.select(alpha)
    _check_eq(selection.selected_squad, alpha, "selected squad state")
    _check_eq(selection.get_selected_squad_id(), &"alpha", "selected squad id")
    selection.select(alpha)
    _check_eq(changes, [alpha], "reselecting the same squad emits once")
    alpha.board_position = Vector2(5.0, 5.0)
    _check_eq(selection.selected_squad, alpha, "selection unaffected by position change")
    selection.free()


func test_selecting_another_squad_replaces_selection() -> void:
    var selection := SelectionManager.new()
    var alpha := _make_state(&"alpha", P1)
    var bravo := _make_state(&"bravo", P2)
    selection.select(alpha)
    selection.select(bravo)
    _check_eq(selection.selected_squad, bravo, "selection moved to the other player's squad")
    _check_eq(selection.get_selected_squad_id(), &"bravo", "selected id updated")
    selection.free()


func test_clear_selection() -> void:
    var selection := SelectionManager.new()
    var alpha := _make_state(&"alpha", P1)
    var changes := []
    selection.selection_changed.connect(func(s): changes.append(s))
    selection.select(alpha)
    selection.clear_selection()
    _check_eq(selection.selected_squad, null, "nothing selected")
    _check_eq(selection.get_selected_squad_id(), &"", "no selected id")
    _check_eq(changes, [alpha, null], "selection_changed reports the clear")
    selection.free()


func test_selection_cleared_when_selected_squad_removed() -> void:
    var battle := BattleState.new()
    var selection := SelectionManager.new()
    selection.bind_battle(battle)
    var alpha := _make_state(&"alpha", P1)
    var bravo := _make_state(&"bravo", P2)
    battle.add_squad(alpha)
    battle.add_squad(bravo)
    selection.select(alpha)
    battle.remove_squad(&"bravo")
    _check_eq(selection.selected_squad, alpha, "removing another squad keeps the selection")
    battle.remove_squad(&"alpha")
    _check_eq(selection.selected_squad, null, "removing the selected squad clears the selection")
    selection.free()


func test_info_panel_shows_selected_squad() -> void:
    var panel: SquadInfoPanel = load("res://scenes/ui/SquadInfoPanel.tscn").instantiate()
    root.add_child(panel)
    _check_eq(panel.name_label.text, SquadInfoPanel.EMPTY_TEXT, "empty state on start")
    _check(not panel.stats_grid.visible, "stats hidden when empty")
    var state := SquadState.new(load("res://data/squads/p2_raider_squad.tres"), Vector2(1.0, 1.0))
    var squad := state.data
    panel.show_squad(state)
    _check_eq(panel.name_label.text, squad.display_name, "name")
    _check_eq(panel.player_label.text, "Player 2", "affiliation")
    _check(panel.stats_grid.visible, "stats shown")
    _check_eq(panel.movement_value.text, String.num(squad.profile.movement), "M")
    _check_eq(panel.quality_value.text, str(squad.profile.quality), "Q")
    _check_eq(panel.toughness_value.text, str(squad.profile.toughness), "T")
    _check_eq(panel.wounds_value.text, str(squad.profile.wounds), "W")
    _check_eq(panel.leadership_value.text, str(squad.profile.leadership), "Ld")
    panel.show_squad(null)
    _check_eq(panel.name_label.text, SquadInfoPanel.EMPTY_TEXT, "empty state after clearing")
    _check(not panel.player_label.visible and not panel.stats_grid.visible, "details hidden after clearing")
    panel.free()


func test_click_selection_in_main_scene() -> void:
    var main: Node = await _load_main()
    var layer: SquadLayer = main.get_node("GameBoard/Squads")
    var selection: SelectionManager = main.get_node("SelectionManager")
    var panel: SquadInfoPanel = main.get_node("HUD/SquadInfoPanel")
    var tm: TurnManager = main.get_node("TurnManager")
    var board: GameBoard = main.get_node("GameBoard")
    var p1_squad: SquadState = main.battle.get_squad(&"p1_line_squad")
    var p2_squad: SquadState = main.battle.get_squad(&"p2_raider_squad")
    var p1_token := layer.get_token(&"p1_line_squad")
    var p2_token := layer.get_token(&"p2_raider_squad")
    var turn_state := [tm.current_phase, tm.turn_number, tm.priority_player, tm.state]

    _click(p1_token.global_position + Vector2(5.0, -5.0))
    _check_eq(selection.selected_squad, p1_squad, "click selects Line Squad's state")
    _check(p1_token.selected and not p2_token.selected, "only Line Squad shows selection")
    _check_eq(panel.name_label.text, p1_squad.data.display_name, "panel shows Line Squad")

    _click(p2_token.global_position)
    _check_eq(selection.selected_squad, p2_squad, "click transfers selection to Raider Squad's state")
    _check(p2_token.selected and not p1_token.selected, "only Raider Squad shows selection")
    _check_eq(panel.player_label.text, "Player 2", "panel shows Player 2")

    var empty_point := board.global_position + board.units_to_pixels(Vector2(24.0, 4.0))
    _check_eq(layer.token_at(layer.to_local(empty_point)), null, "test point is empty battlefield")
    _click(empty_point)
    _check_eq(selection.selected_squad, null, "clicking empty space clears selection")
    _check(not p1_token.selected and not p2_token.selected, "no squad shows selection")
    _check_eq(panel.name_label.text, SquadInfoPanel.EMPTY_TEXT, "panel shows empty state")

    _click(p1_token.global_position)
    main.battle.remove_squad(&"p1_line_squad")
    _check_eq(selection.selected_squad, null, "removing the selected squad clears selection in Main")
    _check_eq(panel.name_label.text, SquadInfoPanel.EMPTY_TEXT, "panel cleared after removal")

    _check_eq([tm.current_phase, tm.turn_number, tm.priority_player, tm.state], turn_state,
        "selection leaves turn state untouched")
    main.queue_free()
    await process_frame


## A MovementController bound to a fresh battle and a started TurnManager.
func _movement_fixture(squads: Array) -> Dictionary:
    var battle := BattleState.new()
    for state in squads:
        battle.add_squad(state)
    var tm := TurnManager.new()
    var movement := MovementController.new()
    movement.bind(battle, tm, Vector2(48.0, 32.0))
    tm.start_game()
    return {"battle": battle, "tm": tm, "movement": movement}


func _free_fixture(fixture: Dictionary) -> void:
    fixture.tm.free()
    fixture.movement.free()


func _make_mover(m: float, position: Vector2) -> SquadState:
    # Temporary test fixture values, not game balance data.
    var state := _make_state(&"mover", P1, position)
    state.data.profile.movement = m
    return state


func test_movement_allowance_from_profile() -> void:
    var line: SquadData = load("res://data/squads/p1_line_squad.tres")
    _check_eq(MovementRules.allowance_for(line), line.profile.movement, "allowance is the profile's M")
    _check_eq(MovementRules.allowance_for(null), 0.0, "no data, no movement")
    var fixture := _movement_fixture([_make_mover(4.5, Vector2(10.0, 10.0))])
    var state: SquadState = fixture.battle.get_squad(&"mover")
    _check_eq(state.movement_allowance, 4.5, "allowance set from M at turn start")
    _check_eq(state.turn_start_position, Vector2(10.0, 10.0), "turn start position recorded")
    _check(not state.movement_complete, "movement not complete at turn start")
    _free_fixture(fixture)


func test_movement_distance_is_continuous() -> void:
    _check_eq(MovementRules.distance(Vector2(0.0, 0.0), Vector2(3.0, 4.0)), 5.0, "3-4-5 diagonal")
    _check(is_equal_approx(MovementRules.distance(Vector2(1.25, 2.5), Vector2(2.75, 4.5)), 2.5),
        "fractional off-grid distance")
    _check_eq(MovementRules.distance(Vector2(7.0, 7.0), Vector2(7.0, 7.0)), 0.0, "zero distance")


func test_valid_order_updates_authoritative_state() -> void:
    var fixture := _movement_fixture([_make_mover(6.0, Vector2(10.0, 10.0))])
    var state: SquadState = fixture.battle.get_squad(&"mover")
    var ordered := []
    fixture.movement.move_ordered.connect(func(s, from, to): ordered.append([s, from, to]))
    var result: MovementRules.Result = fixture.movement.order_move(state, Vector2(13.0, 14.0))
    _check_eq(result, MovementRules.Result.OK, "order accepted")
    _check_eq(state.board_position, Vector2(13.0, 14.0), "position updated")
    _check_eq(state.distance_moved, 5.0, "distance moved tracked")
    _check(is_equal_approx(state.get_remaining_movement(), 1.0), "remaining movement")
    _check(not state.movement_complete, "movement not yet complete")
    _check_eq(ordered, [[state, Vector2(10.0, 10.0), Vector2(13.0, 14.0)]], "move_ordered reported")
    _free_fixture(fixture)


func test_invalid_orders_leave_state_unchanged() -> void:
    var fixture := _movement_fixture([_make_mover(6.0, Vector2(2.0, 2.0))])
    var state: SquadState = fixture.battle.get_squad(&"mover")
    var rejected := []
    fixture.movement.move_rejected.connect(func(_s, _d, r): rejected.append(r))
    _check_eq(fixture.movement.order_move(state, Vector2(9.0, 2.0)), MovementRules.Result.OUT_OF_RANGE, "7 > 6 rejected")
    _check_eq(fixture.movement.order_move(state, Vector2(-1.0, 2.0)), MovementRules.Result.OFF_BOARD, "off-board rejected")
    _check_eq(fixture.movement.order_move(null, Vector2(3.0, 3.0)), MovementRules.Result.NO_SQUAD, "no squad rejected")
    _check_eq(rejected, [MovementRules.Result.OUT_OF_RANGE, MovementRules.Result.OFF_BOARD, MovementRules.Result.NO_SQUAD],
        "move_rejected reported")
    _check_eq(state.board_position, Vector2(2.0, 2.0), "position unchanged")
    _check_eq(state.turn_start_position, Vector2(2.0, 2.0), "turn start unchanged")
    _check_eq(state.distance_moved, 0.0, "nothing moved")
    _check(not state.movement_complete, "still free to move")
    _free_fixture(fixture)


func test_allowance_measured_from_turn_start() -> void:
    var fixture := _movement_fixture([_make_mover(6.0, Vector2(10.0, 10.0))])
    var state: SquadState = fixture.battle.get_squad(&"mover")
    var movement: MovementController = fixture.movement
    _check_eq(movement.order_move(state, Vector2(14.0, 10.0)), MovementRules.Result.OK, "first order of 4")
    _check_eq(movement.order_move(state, Vector2(17.0, 10.0)), MovementRules.Result.OUT_OF_RANGE,
        "7 from turn start rejected even though only 3 from current position")
    _check_eq(state.board_position, Vector2(14.0, 10.0), "rejected order left position")
    _check_eq(movement.order_move(state, Vector2(10.0, 15.5)), MovementRules.Result.OK, "5.5 from turn start accepted")
    _check(is_equal_approx(state.distance_moved, 5.5), "distance measured from turn start")
    _check_eq(movement.order_move(state, Vector2(16.0, 10.0)), MovementRules.Result.OK, "exactly the allowance accepted")
    _check(state.movement_complete, "full allowance used completes movement")
    _check_eq(movement.order_move(state, Vector2(12.0, 10.0)), MovementRules.Result.MOVEMENT_COMPLETE,
        "no further orders once complete")
    _check_eq(state.board_position, Vector2(16.0, 10.0), "position held after exhaustion")
    _free_fixture(fixture)


func test_no_move_orders_outside_movement_phase() -> void:
    var fixture := _movement_fixture([_make_mover(6.0, Vector2(10.0, 10.0))])
    var state: SquadState = fixture.battle.get_squad(&"mover")
    var tm: TurnManager = fixture.tm
    for phase in [Phase.SHOOTING, Phase.ASSAULT, Phase.MORALE]:
        _play_phase(tm, 1, 1)
        _check_eq(tm.current_phase, phase, "advanced to %s" % TurnManager.phase_to_string(phase))
        _check_eq(fixture.movement.order_move(state, Vector2(11.0, 10.0)), MovementRules.Result.WRONG_PHASE,
            "rejected in %s" % TurnManager.phase_to_string(phase))
    _check_eq(state.board_position, Vector2(10.0, 10.0), "position unchanged")
    _free_fixture(fixture)


func test_movement_resets_at_new_turn() -> void:
    var fixture := _movement_fixture([_make_mover(6.0, Vector2(10.0, 10.0))])
    var state: SquadState = fixture.battle.get_squad(&"mover")
    var tm: TurnManager = fixture.tm
    fixture.movement.order_move(state, Vector2(16.0, 10.0))
    _check(state.movement_complete, "complete in turn 1")
    for i in 3:
        _play_phase(tm, 1, 1)
    _check(state.movement_complete, "no reset during the same turn")
    _check_eq(state.turn_start_position, Vector2(10.0, 10.0), "turn start kept until turn ends")
    _play_phase(tm, 1, 1)
    _check_eq(tm.turn_number, 2, "turn 2 started")
    _check(not state.movement_complete, "movement available again")
    _check_eq(state.turn_start_position, Vector2(16.0, 10.0), "turn starts from current position")
    _check_eq(state.distance_moved, 0.0, "distance reset")
    _check_eq(state.movement_allowance, 6.0, "allowance re-derived from M")
    _check_eq(fixture.movement.order_move(state, Vector2(22.0, 10.0)), MovementRules.Result.OK, "can move again")
    _free_fixture(fixture)


func test_squad_added_mid_game_gets_movement() -> void:
    var fixture := _movement_fixture([])
    var late := _make_mover(5.0, Vector2(3.0, 3.0))
    fixture.battle.add_squad(late)
    _check_eq(late.movement_allowance, 5.0, "allowance set when added")
    _free_fixture(fixture)


func test_move_order_in_main_scene() -> void:
    var main: Node = await _load_main()
    var board: GameBoard = main.get_node("GameBoard")
    var layer: SquadLayer = main.get_node("GameBoard/Squads")
    var overlay: MovementOverlay = main.get_node("GameBoard/MovementOverlay")
    var panel: SquadInfoPanel = main.get_node("HUD/SquadInfoPanel")
    var feedback: Label = main.get_node("HUD/OrderFeedback")
    var selection: SelectionManager = main.get_node("SelectionManager")
    var tm: TurnManager = main.get_node("TurnManager")
    var squad: SquadState = main.battle.get_squad(&"p1_line_squad")
    var token := layer.get_token(&"p1_line_squad")
    var allowance := squad.data.profile.movement

    _right_click(board.global_position + board.units_to_pixels(Vector2(14.0, 16.0)))
    _check_eq(feedback.text, "Select a squad to move", "feedback with nothing selected")

    _click(token.global_position)
    _check_eq(selection.selected_squad, squad, "Line Squad selected")
    _right_click(board.global_position + board.units_to_pixels(squad.board_position + Vector2(1.0, 0.0)))
    _check_eq(feedback.text, "Activate Line Squad before moving it", "orders need an activation")
    var activation := main.get_node("ActivationController") as ActivationController
    _check_eq(activation.activate(squad), ActivationController.Result.OK, "Line Squad activated")
    var turn_state := [tm.current_phase, tm.turn_number, tm.priority_player, tm.state]
    var start := squad.board_position
    var destination := start + Vector2(3.0, 4.0)
    _right_click(board.global_position + board.units_to_pixels(destination))
    _check(squad.board_position.is_equal_approx(destination), "right-click moves the authoritative position")
    _check(is_equal_approx(squad.distance_moved, 5.0), "distance tracked")
    _check(token.is_moving(), "token animating toward the destination")
    _check(token.selected, "selection ring kept while moving")
    _check_eq(selection.selected_squad, squad, "still selected while moving")
    _check(feedback.text.begins_with(squad.data.display_name + " moving"), "order feedback shown")
    _check(panel.movement_label.text.begins_with("Moved 5.0 / "), "panel shows distance moved")
    _check_eq(panel.name_label.text, squad.data.display_name, "panel still shows the squad")
    for i in 120:
        await process_frame
        if not token.is_moving():
            break
    _check(not token.is_moving(), "token arrived")
    _check(token.position.is_equal_approx(board.units_to_pixels(destination)), "token at the authoritative position")

    var too_far := start + Vector2(allowance + 1.0, 0.0)
    _right_click(board.global_position + board.units_to_pixels(too_far))
    _check(squad.board_position.is_equal_approx(destination), "out-of-range order leaves position")
    _check(feedback.text.begins_with("Out of range"), "out-of-range feedback")
    _check(overlay.is_showing_rejection(), "rejected destination marked")

    _check_eq([tm.current_phase, tm.turn_number, tm.priority_player, tm.state], turn_state,
        "movement leaves turn state untouched")
    main.queue_free()
    await process_frame


## Activates and ends every squad that may activate until the current phase
## ends. Returns the squad ids in activation order.
func _complete_phase(activation: ActivationController, battle: BattleState, tm: TurnManager) -> Array:
    var phase := tm.current_phase
    var turn := tm.turn_number
    var order := []
    while tm.current_phase == phase and tm.turn_number == turn and order.size() <= battle.get_squads().size():
        var next: SquadState = null
        for state in battle.get_squads():
            if activation.can_activate(state) == ActivationController.Result.OK:
                next = state
                break
        if next == null:
            break
        activation.activate(next)
        order.append(next.squad_id)
        activation.end_activation()
    return order


## A started game with `p1` and `p2` squads per player and an ActivationController.
func _activation_fixture(p1: int, p2: int) -> Dictionary:
    var battle := BattleState.new()
    for i in p1:
        battle.add_squad(_make_state(StringName("p1_%d" % i), P1, Vector2(5.0 + i, 5.0)))
    for i in p2:
        battle.add_squad(_make_state(StringName("p2_%d" % i), P2, Vector2(5.0 + i, 20.0)))
    for state in battle.get_squads():
        # Temporary test fixture value, not game balance data.
        state.data.profile.movement = 6.0
    var tm := TurnManager.new()
    var activation := ActivationController.new()
    activation.bind(battle, tm)
    var movement := MovementController.new()
    movement.bind(battle, tm, Vector2(48.0, 32.0))
    movement.activation = activation
    tm.start_game()
    return {"battle": battle, "tm": tm, "activation": activation, "movement": movement}


func _free_activation_fixture(fixture: Dictionary) -> void:
    fixture.tm.free()
    fixture.activation.free()
    fixture.movement.free()


func test_activation_starts_movement_phase_with_squad_counts() -> void:
    var f := _activation_fixture(2, 3)
    var tm: TurnManager = f.tm
    _check_eq(tm.state, TurnManager.State.IN_PHASE, "phase begun automatically")
    _check_eq(tm.get_remaining_activations(P1), 2, "Player 1 eligible squads")
    _check_eq(tm.get_remaining_activations(P2), 3, "Player 2 eligible squads")
    _check_eq(f.activation.get_active_player(), P2, "more squads takes priority")
    _free_activation_fixture(f)


func test_players_alternate_squad_activations() -> void:
    var f := _activation_fixture(2, 2)
    var players := []
    var battle: BattleState = f.battle
    for id in _complete_phase(f.activation, battle, f.tm):
        players.append(battle.get_squad(id).get_player())
    _check_eq(players, [P1, P2, P1, P2], "activations alternate starting with Player 1")
    _free_activation_fixture(f)


func test_squad_ownership_enforced() -> void:
    var f := _activation_fixture(1, 1)
    var activation: ActivationController = f.activation
    var p1_squad: SquadState = f.battle.get_squad(&"p1_0")
    var p2_squad: SquadState = f.battle.get_squad(&"p2_0")
    _check_eq(activation.get_active_player(), P1, "Player 1 to activate")
    _check_eq(activation.activate(p2_squad), ActivationController.Result.WRONG_PLAYER, "opponent's squad refused")
    _check_eq(activation.active_squad, null, "nothing activated")
    _check_eq(activation.activate(p1_squad), ActivationController.Result.OK, "own squad accepted")
    _check_eq(activation.activate(p2_squad), ActivationController.Result.ACTIVATION_IN_PROGRESS,
        "no second activation while one is running")
    activation.end_activation()
    _check_eq(activation.get_active_player(), P2, "control passes to Player 2")
    _check_eq(activation.activate(p1_squad), ActivationController.Result.ALREADY_ACTIVATED, "Player 1's spent squad refused")
    _check_eq(activation.activate(p2_squad), ActivationController.Result.OK, "Player 2 activates")
    _free_activation_fixture(f)


func test_squad_cannot_activate_twice_in_a_phase() -> void:
    var f := _activation_fixture(2, 1)
    var activation: ActivationController = f.activation
    var first: SquadState = f.battle.get_squad(&"p1_0")
    activation.activate(first)
    activation.end_activation()
    activation.activate(f.battle.get_squad(&"p2_0"))
    activation.end_activation()
    _check_eq(activation.get_active_player(), P1, "Player 1 again")
    _check(activation.has_activated(first), "first squad marked activated")
    _check_eq(activation.activate(first), ActivationController.Result.ALREADY_ACTIVATED, "second activation refused")
    _check_eq(activation.activate(f.battle.get_squad(&"p1_1")), ActivationController.Result.OK,
        "the player's other squad may activate")
    _free_activation_fixture(f)


func test_all_squads_activate_and_phase_advances() -> void:
    var f := _activation_fixture(2, 2)
    var tm: TurnManager = f.tm
    var order := _complete_phase(f.activation, f.battle, tm)
    _check_eq(order.size(), 4, "every squad activated once")
    _check_eq(tm.current_phase, Phase.SHOOTING, "advanced to Shooting")
    _check_eq(tm.state, TurnManager.State.IN_PHASE, "Shooting begun automatically")
    _check_eq(f.activation.get_activated_squads(), [], "activation record cleared for the new phase")
    _free_activation_fixture(f)


func test_player_without_squads_does_not_block_opponent() -> void:
    var f := _activation_fixture(3, 1)
    var battle: BattleState = f.battle
    var players := []
    for id in _complete_phase(f.activation, battle, f.tm):
        players.append(battle.get_squad(id).get_player())
    _check_eq(players, [P1, P2, P1, P1], "Player 1 continues after Player 2 runs out")
    _check_eq(f.tm.current_phase, Phase.SHOOTING, "phase advanced")
    _free_activation_fixture(f)


func test_full_progression_through_all_phases() -> void:
    var f := _activation_fixture(1, 1)
    var tm: TurnManager = f.tm
    var phases := []
    tm.phase_started.connect(func(phase, _turn, _priority): phases.append(phase))
    for i in 3:
        _complete_phase(f.activation, f.battle, tm)
    _check_eq(phases, [Phase.SHOOTING, Phase.ASSAULT, Phase.MORALE, Phase.MOVEMENT],
        "Shooting, Assault, Morale (no tests, passes at once), then Movement")
    _check_eq(tm.turn_number, 2, "new turn")
    _check_eq(tm.current_phase, Phase.MOVEMENT, "back to Movement")
    _free_activation_fixture(f)


func test_new_turn_resets_activation_state() -> void:
    var f := _activation_fixture(1, 1)
    var activation: ActivationController = f.activation
    var squad: SquadState = f.battle.get_squad(&"p1_0")
    activation.activate(squad)
    activation.end_activation()
    _check(activation.has_activated(squad), "activated in turn 1 Movement")
    activation.activate(f.battle.get_squad(&"p2_0"))
    activation.end_activation()
    for i in 2:
        _complete_phase(activation, f.battle, f.tm)
    _check_eq(f.tm.turn_number, 2, "turn 2")
    _check(not activation.has_activated(squad), "squad may activate again")
    _check_eq(activation.can_activate(squad), ActivationController.Result.OK, "activation available")
    _free_activation_fixture(f)


func test_movement_resets_at_turn_boundary_not_between_phases() -> void:
    var f := _activation_fixture(1, 1)
    var activation: ActivationController = f.activation
    var movement: MovementController = f.movement
    var squad: SquadState = f.battle.get_squad(&"p1_0")
    _check_eq(movement.order_move(squad, squad.board_position + Vector2(1.0, 0.0)),
        MovementRules.Result.NOT_ACTIVATED, "move refused before activation")
    activation.activate(squad)
    var start := squad.board_position
    _check_eq(movement.order_move(squad, start + Vector2(3.0, 4.0)), MovementRules.Result.OK, "activated squad moves")
    activation.end_activation()
    _check_eq(movement.order_move(squad, start), MovementRules.Result.NOT_ACTIVATED, "no moves after its activation")
    _complete_phase(activation, f.battle, f.tm)
    _check_eq(f.tm.current_phase, Phase.SHOOTING, "in Shooting")
    _check_eq(squad.distance_moved, 5.0, "movement tracking kept between phases")
    _check_eq(squad.turn_start_position, start, "turn start kept between phases")
    _complete_phase(activation, f.battle, f.tm)
    _complete_phase(activation, f.battle, f.tm)
    _check_eq(f.tm.turn_number, 2, "turn 2")
    _check_eq(squad.distance_moved, 0.0, "movement reset at the new turn")
    _check_eq(squad.turn_start_position, start + Vector2(3.0, 4.0), "turn starts where the squad stands")
    _free_activation_fixture(f)


func test_removed_squads_update_activation() -> void:
    var f := _activation_fixture(2, 1)
    var activation: ActivationController = f.activation
    var tm: TurnManager = f.tm
    f.battle.remove_squad(&"p1_1")
    _check_eq(tm.get_remaining_activations(P1), 1, "waiting squad removed from the count")
    activation.activate(f.battle.get_squad(&"p1_0"))
    f.battle.remove_squad(&"p1_0")
    _check_eq(activation.active_squad, null, "removing the active squad ends its activation")
    _check_eq(activation.get_active_player(), P2, "play passes on")
    _free_activation_fixture(f)


func test_activation_panel_and_tokens_in_main_scene() -> void:
    var main: Node = await _load_main()
    var panel: ActivationPanel = main.get_node("HUD/ActivationPanel")
    var layer: SquadLayer = main.get_node("GameBoard/Squads")
    var selection: SelectionManager = main.get_node("SelectionManager")
    var activation: ActivationController = main.get_node("ActivationController")
    var p1_squad: SquadState = main.battle.get_squad(&"p1_line_squad")
    var p2_squad: SquadState = main.battle.get_squad(&"p2_raider_squad")
    _check_eq(panel.player_label.text, "Player 1 to activate", "entitled player shown")
    _check(panel.action_button.disabled, "nothing selected, nothing to activate")

    _click(layer.get_token(&"p2_raider_squad").global_position)
    _check_eq(selection.selected_squad, p2_squad, "opponent squad selectable for inspection")
    _check(panel.action_button.disabled, "cannot activate opponent's squad")
    _check_eq(panel.hint_label.text, "Not Player 1's squad", "reason shown")

    _click(layer.get_token(&"p1_line_squad").global_position)
    _check(not panel.action_button.disabled, "own squad can be activated")
    panel.action_button.pressed.emit()
    _check(activation.is_active_squad(p1_squad), "button activates the selected squad")
    _check_eq(panel.active_label.text, "Active: Line Squad", "active squad shown")
    _check_eq(layer.get_token(&"p1_line_squad").activation_display, SquadToken.ActivationDisplay.ACTIVE, "token marked active")
    _check_eq(panel.action_button.text, "End activation", "button offers to end the activation")

    panel.action_button.pressed.emit()
    _check_eq(activation.active_squad, null, "activation ended")
    _check_eq(panel.player_label.text, "Player 2 to activate", "control passed")
    _check_eq(panel.activated_label.text, "Done: Line Squad", "activated squads listed")
    _check_eq(layer.get_token(&"p1_line_squad").activation_display, SquadToken.ActivationDisplay.SPENT, "token marked spent")
    _check_eq(panel.hint_label.text, "Already activated this phase", "selected squad already spent")
    main.queue_free()
    await process_frame


## A weapon for tests. Temporary fixture values, not game balance data.
func _make_weapon(weapon_range: float, attacks: int) -> WeaponProfile:
    var weapon := WeaponProfile.new()
    weapon.weapon_name = "Gun %s" % weapon_range
    weapon.range = weapon_range
    weapon.attacks = attacks
    return weapon


## A squad whose models are given as [name, weapon or null, offset] entries.
## Temporary fixture values, not game balance data.
func _make_shooter(squad_id: StringName, player: int, position: Vector2, models: Array,
        quality := 4, wounds := 1) -> SquadState:
    var squad := SquadData.new()
    squad.squad_id = squad_id
    squad.display_name = String(squad_id)
    squad.player = player
    squad.profile = UnitProfile.new()
    squad.profile.quality = quality
    squad.profile.movement = 6.0
    squad.profile.wounds = wounds
    for entry in models:
        var model := SquadModel.new()
        model.model_name = entry[0]
        model.weapon = entry[1]
        model.formation_offset = entry[2]
        squad.models.append(model)
    return SquadState.new(squad, position)


func test_placeholder_weapons_differ() -> void:
    var rifle: WeaponProfile = load("res://data/weapons/rifle.tres")
    var pistol: WeaponProfile = load("res://data/weapons/pistol.tres")
    var heavy: WeaponProfile = load("res://data/weapons/heavy_gun.tres")
    _check_eq([rifle.weapon_name, pistol.weapon_name, heavy.weapon_name], ["Rifle", "Pistol", "Heavy Gun"], "names")
    _check(rifle.range != pistol.range and heavy.range != rifle.range, "different ranges")
    _check(heavy.attacks != rifle.attacks, "different attack counts")
    var line: SquadData = load("res://data/squads/p1_line_squad.tres")
    _check_eq(line.models.size(), 4, "Line Squad lists its models")
    _check_eq(line.models[3].weapon, heavy, "models reference shared weapon profiles")


func test_model_eligibility_reasons() -> void:
    var los := LineOfSight.new()
    var targets: Array[Vector2] = [Vector2(20.0, 10.0)]
    var gun := _make_weapon(12.0, 1)
    var r := ShootingRules.evaluate_model("A", gun, Vector2(10.0, 10.0), targets, los)
    _check_eq(r.eligibility, ShootingRules.Eligibility.ELIGIBLE, "weapon, range and line of sight: can fire")
    _check_eq(r.distance, 10.0, "distance to target")
    r = ShootingRules.evaluate_model("B", gun, Vector2(5.0, 10.0), targets, los)
    _check_eq(r.eligibility, ShootingRules.Eligibility.OUT_OF_RANGE, "15 > 12: out of range")
    r = ShootingRules.evaluate_model("C", null, Vector2(10.0, 10.0), targets, los)
    _check_eq(r.eligibility, ShootingRules.Eligibility.NO_RANGED_WEAPON, "no weapon")
    r = ShootingRules.evaluate_model("D", _make_weapon(0.0, 1), Vector2(10.0, 10.0), targets, los)
    _check_eq(r.eligibility, ShootingRules.Eligibility.NO_RANGED_WEAPON, "range 0 is not a ranged weapon")
    los.add_blocker(Rect2(14.0, 8.0, 2.0, 4.0))
    r = ShootingRules.evaluate_model("E", gun, Vector2(10.0, 10.0), targets, los)
    _check_eq(r.eligibility, ShootingRules.Eligibility.NO_LINE_OF_SIGHT, "blocked: no line of sight")


func test_range_boundaries() -> void:
    var gun := _make_weapon(12.0, 1)
    _check(ShootingRules.in_range(gun, 11.5), "within range")
    _check(ShootingRules.in_range(gun, 12.0), "exactly at maximum range")
    _check(not ShootingRules.in_range(gun, 12.01), "beyond maximum range")
    var los := LineOfSight.new()
    var exact: Array[Vector2] = [Vector2(13.0, 1.0)]
    _check_eq(ShootingRules.evaluate_model("A", gun, Vector2(1.0, 1.0), exact, los).eligibility,
        ShootingRules.Eligibility.ELIGIBLE, "model exactly 12 away can fire")


func test_line_of_sight_query() -> void:
    var los := LineOfSight.new()
    _check(los.has_line_of_sight(Vector2(0.0, 0.0), Vector2(40.0, 30.0)), "clear with no blockers")
    los.add_blocker(Rect2(10.0, 4.0, 2.0, 2.0))
    _check(not los.has_line_of_sight(Vector2(0.0, 5.0), Vector2(20.0, 5.0)), "blocker on the line blocks")
    _check(los.has_line_of_sight(Vector2(0.0, 0.0), Vector2(20.0, 0.0)), "blocker off the line does not block")
    _check(not los.has_line_of_sight(Vector2(11.0, 5.0), Vector2(20.0, 5.0)), "line starting inside a blocker is blocked")
    los.clear_blockers()
    _check(los.has_line_of_sight(Vector2(0.0, 5.0), Vector2(20.0, 5.0)), "clear again once removed")


func test_line_of_sight_to_any_target_model() -> void:
    var los := LineOfSight.new()
    los.add_blocker(Rect2(14.0, 9.0, 2.0, 2.0))
    var targets: Array[Vector2] = [Vector2(20.0, 10.0), Vector2(20.0, 14.0)]
    var r := ShootingRules.evaluate_model("A", _make_weapon(12.0, 1), Vector2(10.0, 10.0), targets, los)
    _check_eq(r.eligibility, ShootingRules.Eligibility.ELIGIBLE, "a visible target model in range is enough")


func test_hit_rolls_against_quality() -> void:
    _check(ShootingRules.is_hit(4, 4), "roll equal to Quality hits")
    _check(ShootingRules.is_hit(6, 4), "roll above Quality hits")
    _check(not ShootingRules.is_hit(3, 4), "roll below Quality misses")
    var dice := ScriptedDice.new([4, 3, 6])
    _check_eq(ShootingRules.roll_attacks(3, dice), [4, 3, 6], "one independent roll per attack")
    var seeded_a := DiceRoller.new(42)
    var seeded_b := DiceRoller.new(42)
    var a := []
    var b := []
    for i in 20:
        a.append(seeded_a.roll_d6())
        b.append(seeded_b.roll_d6())
    _check_eq(a, b, "seeded dice repeat")
    _check(a.all(func(v): return v >= 1 and v <= 6), "rolls are D6 values")


func test_resolve_per_model_and_totals() -> void:
    # Temporary fixture values, not game balance data.
    var firing := _make_shooter(&"shooters", P1, Vector2(10.0, 10.0), [
        ["Leader", _make_weapon(6.0, 1), Vector2.ZERO],
        ["Rifle", _make_weapon(24.0, 1), Vector2(0.0, 1.0)],
        ["Heavy", _make_weapon(24.0, 3), Vector2(0.0, -1.0)],
        ["Unarmed", null, Vector2(1.0, 0.0)],
    ], 4)
    var target := _make_shooter(&"target", P2, Vector2(30.0, 10.0), [["T", null, Vector2.ZERO]])
    var result := ShootingRules.resolve(firing, target, LineOfSight.new(), ScriptedDice.new([5, 2, 4, 6]))
    _check_eq(result.firing_squad, firing, "firing squad")
    _check_eq(result.target_squad, target, "target squad")
    _check_eq(result.get_eligible_count(), 2, "rifle and heavy fire")
    _check_eq(result.get_ineligible_count(), 2, "leader out of range, unarmed model")
    _check_eq(result.model_results[0].eligibility, ShootingRules.Eligibility.OUT_OF_RANGE, "leader reason")
    _check_eq(result.model_results[3].eligibility, ShootingRules.Eligibility.NO_RANGED_WEAPON, "unarmed reason")
    _check_eq(result.model_results[1].rolls, [5], "rifle rolled once")
    _check_eq(result.model_results[2].rolls, [2, 4, 6], "heavy rolled three times")
    _check_eq(result.get_total_attacks(), 4, "total attacks")
    _check_eq(result.get_hits(), 3, "5, 4 and 6 hit on Quality 4")
    _check_eq(result.get_misses(), 1, "the 2 misses")


func test_zero_eligible_models_is_a_valid_result() -> void:
    var firing := _make_shooter(&"shooters", P1, Vector2(1.0, 1.0), [
        ["Pistol", _make_weapon(6.0, 1), Vector2.ZERO], ["Unarmed", null, Vector2(1.0, 0.0)]])
    var target := _make_shooter(&"target", P2, Vector2(40.0, 30.0), [["T", null, Vector2.ZERO]])
    var result := ShootingRules.resolve(firing, target, LineOfSight.new(), ScriptedDice.new([]))
    _check_eq(result.model_results.size(), 2, "both models reported")
    _check_eq([result.get_eligible_count(), result.get_total_attacks(), result.get_hits(), result.get_misses()],
        [0, 0, 0, 0], "zero shots")


## A started game with shooters for both players and all controllers bound.
func _shooting_fixture(extra_p1 := false) -> Dictionary:
    var battle := BattleState.new()
    var rifle := _make_weapon(24.0, 1)
    battle.add_squad(_make_shooter(&"p1_a", P1, Vector2(10.0, 10.0), [["Rifle", rifle, Vector2.ZERO]]))
    if extra_p1:
        battle.add_squad(_make_shooter(&"p1_b", P1, Vector2(10.0, 20.0), [["Rifle", rifle, Vector2.ZERO]]))
    battle.add_squad(_make_shooter(&"p2_a", P2, Vector2(30.0, 10.0), [["Rifle", rifle, Vector2.ZERO]]))
    var tm := TurnManager.new()
    var activation := ActivationController.new()
    activation.bind(battle, tm)
    var shooting := ShootingController.new()
    shooting.bind(tm, activation, battle)
    # Rifles (S0) against T0 wound on 2+; neither squad has an armor save.
    shooting.dice = ScriptedDice.new([6, 6, 6, 6, 6, 6])
    tm.start_game()
    return {"battle": battle, "tm": tm, "activation": activation, "shooting": shooting}


func _free_shooting_fixture(f: Dictionary) -> void:
    f.tm.free()
    f.activation.free()
    f.shooting.free()


func test_shooting_only_in_shooting_phase() -> void:
    var f := _shooting_fixture()
    var p1: SquadState = f.battle.get_squad(&"p1_a")
    var p2: SquadState = f.battle.get_squad(&"p2_a")
    f.activation.activate(p1)
    _check_eq(f.shooting.order_shot(p1, p2), ShootingRules.OrderResult.WRONG_PHASE, "refused in Movement")
    _check(f.activation.is_active_squad(p1), "refused order does not spend the activation")
    f.activation.end_activation()
    _complete_phase(f.activation, f.battle, f.tm)
    _check_eq(f.tm.current_phase, Phase.SHOOTING, "now Shooting")
    _complete_phase(f.activation, f.battle, f.tm)
    _check_eq(f.tm.current_phase, Phase.ASSAULT, "now Assault")
    f.activation.activate(f.battle.get_squad(&"p1_a"))
    _check_eq(f.shooting.order_shot(p1, p2), ShootingRules.OrderResult.WRONG_PHASE, "refused in Assault")
    _check_eq(ShootingRules.validate_order(p1, p2, Phase.MORALE, true), ShootingRules.OrderResult.WRONG_PHASE,
        "refused in Morale")
    _free_shooting_fixture(f)


## Advances `f` to the Shooting phase of turn 1.
func _to_shooting(f: Dictionary) -> void:
    _complete_phase(f.activation, f.battle, f.tm)


func test_cannot_target_own_squad() -> void:
    var f := _shooting_fixture(true)
    _to_shooting(f)
    var p1: SquadState = f.battle.get_squad(&"p1_a")
    f.activation.activate(p1)
    _check_eq(f.shooting.order_shot(p1, f.battle.get_squad(&"p1_b")), ShootingRules.OrderResult.OWN_SQUAD,
        "own squad refused")
    _check(f.activation.is_active_squad(p1), "activation not spent")
    _free_shooting_fixture(f)


func test_cannot_shoot_with_opponents_squad() -> void:
    var f := _shooting_fixture()
    _to_shooting(f)
    var p1: SquadState = f.battle.get_squad(&"p1_a")
    var p2: SquadState = f.battle.get_squad(&"p2_a")
    _check_eq(f.activation.get_active_player(), P1, "Player 1 to activate")
    _check_eq(f.activation.activate(p2), ActivationController.Result.WRONG_PLAYER, "cannot activate opponent's squad")
    _check_eq(f.shooting.order_shot(p2, p1), ShootingRules.OrderResult.NOT_ACTIVATED, "cannot shoot with it")
    _free_shooting_fixture(f)


func test_shooting_spends_activation_and_passes_control() -> void:
    var f := _shooting_fixture()
    _to_shooting(f)
    var p1: SquadState = f.battle.get_squad(&"p1_a")
    var p2: SquadState = f.battle.get_squad(&"p2_a")
    var results := []
    f.shooting.shot_resolved.connect(func(r): results.append(r))
    # Player 2's squad saves on 4+: hit 6, wound 6, save 4. Player 1's squad has
    # no save: hit 6, wound 6.
    p2.data.profile.armor_save = 4
    f.shooting.dice = ScriptedDice.new([6, 6, 4, 6, 6])
    f.activation.activate(p1)
    _check_eq(f.shooting.order_shot(p1, p2), ShootingRules.OrderResult.OK, "shot accepted")
    _check_eq(results.size(), 1, "result reported")
    _check_eq(results[0].get_hits(), 1, "rifle hit on a 6")
    _check_eq(results[0].get_saves(), 1, "wound saved")
    _check(f.activation.has_activated(p1), "activation spent")
    _check_eq(f.activation.active_squad, null, "no squad active")
    _check_eq(f.activation.get_active_player(), P2, "control passes to Player 2")
    _check_eq(f.shooting.order_shot(p1, p2), ShootingRules.OrderResult.NOT_ACTIVATED, "cannot shoot again")
    _check_eq(f.activation.activate(p1), ActivationController.Result.ALREADY_ACTIVATED, "cannot reactivate")
    f.activation.activate(p2)
    _check_eq(f.shooting.order_shot(p2, p1), ShootingRules.OrderResult.OK, "Player 2 shoots back")
    _check(f.shooting.is_allocation_pending(), "unsaved wound awaits Player 1's allocation")
    _check(f.activation.is_active_squad(p2), "Player 2's activation held open")
    f.shooting.allocate_wound(0)
    _check_eq(f.battle.get_squad(&"p1_a"), null, "Player 1's single model removed, squad destroyed")
    _check_eq(f.activation.active_squad, null, "Player 2's activation completed")
    _check_eq(f.tm.current_phase, Phase.ASSAULT, "phase advances once both have shot")
    _free_shooting_fixture(f)


func test_zero_eligible_shot_still_spends_activation() -> void:
    var f := _shooting_fixture()
    _to_shooting(f)
    var p1: SquadState = f.battle.get_squad(&"p1_a")
    var p2: SquadState = f.battle.get_squad(&"p2_a")
    p2.board_position = Vector2(45.0, 30.0)
    var results := []
    f.shooting.shot_resolved.connect(func(r): results.append(r))
    f.activation.activate(p1)
    _check_eq(f.shooting.order_shot(p1, p2), ShootingRules.OrderResult.OK, "order accepted")
    _check_eq(results[0].get_eligible_count(), 0, "no model in range")
    _check_eq(results[0].get_total_attacks(), 0, "no attacks")
    _check(f.activation.has_activated(p1), "activation spent anyway")
    _check_eq(f.activation.get_active_player(), P2, "control passes")
    _free_shooting_fixture(f)


func test_shooting_in_main_scene() -> void:
    var main: Node = await _load_main()
    var layer: SquadLayer = main.get_node("GameBoard/Squads")
    var activation: ActivationController = main.get_node("ActivationController")
    var shooting: ShootingController = main.get_node("ShootingController")
    var panel: ActivationPanel = main.get_node("HUD/ActivationPanel")
    var feedback: Label = main.get_node("HUD/OrderFeedback")
    var tm: TurnManager = main.get_node("TurnManager")
    # Hits: Trooper rifle 1 (miss); Gunner heavy gun 4, 6, 3 (2 hits on Q4).
    # Wounds: heavy gun S5 vs T3 needs 3+: 5, 2 (1 wound). Save: 5+ with AP1 is 6+: 3 (fails).
    shooting.dice = ScriptedDice.new([1, 4, 6, 3, 5, 2, 3])
    _complete_phase(activation, main.battle, tm)
    _check_eq(tm.current_phase, Phase.SHOOTING, "Shooting phase")
    var line: SquadState = main.battle.get_squad(&"p1_line_squad")
    var raider_token := layer.get_token(&"p2_raider_squad")
    _check_eq(layer.get_token(&"p1_line_squad").model_offsets.size(), 4, "token draws Line Squad's 4 models")

    _right_click(raider_token.global_position)
    _check_eq(feedback.text, "Activate a squad to shoot", "targeting needs an activated squad")
    _click(layer.get_token(&"p1_line_squad").global_position)
    panel.action_button.pressed.emit()
    _check(activation.is_active_squad(line), "Line Squad activated")
    _check_eq(panel.hint_label.text, "Right-click an enemy squad to shoot", "targeting prompt shown")
    _right_click(layer.get_token(&"p1_line_squad").global_position)
    _check_eq(feedback.text, "Cannot shoot your own squad", "own squad refused")
    var allocation: AllocationPanel = main.get_node("HUD/AllocationPanel")
    var raider: SquadState = main.battle.get_squad(&"p2_raider_squad")
    _check(not allocation.visible, "allocation panel hidden before shooting")
    _right_click(raider_token.global_position)
    _check(allocation.visible, "defender asked to allocate the unsaved wound")
    _check_eq(allocation.title_label.text, "Player 2: allocate 1 wound to Raider Squad", "allocation prompt")
    _check_eq(allocation.model_buttons.get_child_count(), 3, "one button per living Raider")
    _check(activation.is_active_squad(line), "shooter's activation held open")
    _check(panel.action_button.disabled, "cannot end the activation mid-allocation")
    _check_eq(panel.hint_label.text, "Waiting for wound allocation", "waiting shown")
    allocation.get_button(1).pressed.emit()
    _check(not allocation.visible, "allocation finished")
    _check(raider.get_model(1).removed, "the chosen Raider is the casualty")
    _check_eq(raider.get_model_count(), 2, "two Raiders left")
    _check_eq(raider_token.model_offsets.size(), 2, "token no longer draws the casualty")
    _check(feedback.text.begins_with("Line Squad shot Raider Squad"), "result shown")
    _check(feedback.text.contains("Wounds 1: 0 saved, 1 unsaved"), "wounds and saves summarised")
    _check(feedback.text.contains("Gunner: 2/3 hit, 1 wnd (3+), 0 saved (6+)"), "Gunner's wound and save detail")
    _check(feedback.text.contains("Casualties: Raider"), "casualty named")
    _check(feedback.text.contains("Raider Squad: 2 models left"), "models remaining")
    # The Sergeant's pistol (12) is out of range, and so is one Trooper: same
    # rifle as the other Trooper, but standing 24.2 from the nearest Raider.
    _check(feedback.text.contains("Fired: 2  Unable: 2"), "per-model eligibility counted")
    _check(feedback.text.contains("Attacks 4: 2 hit, 2 miss"), "rolls 1 (rifle), 4, 6, 3 (heavy gun) on Quality 4")
    _check(feedback.text.contains("Sergeant: out of range"), "Sergeant's reason shown")
    _check(feedback.text.contains("Trooper: out of range"), "out-of-range Trooper's reason shown")
    _check(feedback.text.contains("Gunner: 2/3 hit"), "Gunner's hits shown")
    _check(activation.has_activated(line), "activation spent")
    _check_eq(panel.player_label.text, "Player 2 to activate", "control passed")
    main.queue_free()
    await process_frame


func test_wound_target_table() -> void:
    _check_eq(DamageRules.wound_target(6, 3), 2, "S double T: 2+")
    _check_eq(DamageRules.wound_target(8, 3), 2, "S more than double T: 2+")
    _check_eq(DamageRules.wound_target(5, 3), 3, "S greater than T: 3+")
    _check_eq(DamageRules.wound_target(4, 4), 4, "S equals T: 4+")
    _check_eq(DamageRules.wound_target(3, 4), 5, "S lower than T: 5+")
    _check_eq(DamageRules.wound_target(3, 5), 5, "S lower, but more than half T: 5+")
    _check_eq(DamageRules.wound_target(2, 4), 6, "S half T: 6+")
    _check_eq(DamageRules.wound_target(2, 5), 6, "S less than half T: 6+")


func test_wound_rolls() -> void:
    _check(DamageRules.is_wound(4, 4), "roll equal to target wounds")
    _check(DamageRules.is_wound(6, 3), "roll above target wounds")
    _check(not DamageRules.is_wound(3, 4), "roll below target fails")
    _check(not DamageRules.is_wound(1, 2), "natural 1 fails even against 2+")
    _check(DamageRules.is_wound(2, 2), "2 wounds on 2+")


func test_armor_save_targets_and_rolls() -> void:
    _check_eq(DamageRules.save_target(4, 0), 4, "unmodified 4+")
    _check_eq(DamageRules.save_target(4, 1), 5, "AP1 turns 4+ into 5+")
    _check_eq(DamageRules.save_target(5, 2), 7, "AP2 turns 5+ into 7+")
    _check_eq(DamageRules.save_target(0, 1), 0, "no armor save")
    _check(DamageRules.is_saved(4, 4), "4 saves on 4+")
    _check(not DamageRules.is_saved(3, 4), "3 fails a 4+ save")
    _check(DamageRules.is_saved(6, 6), "6 saves on 6+")
    _check(not DamageRules.can_be_saved(7), "7+ cannot be saved")
    _check(not DamageRules.is_saved(6, 7), "even a 6 fails a 7+ save")
    _check(not DamageRules.is_saved(1, 2), "natural 1 fails even a 2+ save")
    _check(not DamageRules.is_saved(6, 0), "no save, no saving")


func test_wounds_and_saves_resolution() -> void:
    var firing := _make_shooter(&"f", P1, Vector2(10.0, 10.0), [["Gun", _make_weapon(24.0, 4), Vector2.ZERO]])
    firing.data.models[0].weapon.strength = 4
    firing.data.models[0].weapon.armor_piercing = 1
    var target := _make_shooter(&"t", P2, Vector2(20.0, 10.0), [["T", null, Vector2.ZERO]])
    target.data.profile.toughness = 4
    target.data.profile.armor_save = 3
    var dice := ScriptedDice.new([6, 6, 6, 2, 4, 1, 5, 4, 3])
    var result := ShootingRules.resolve(firing, target, LineOfSight.new(), dice)
    _check_eq(result.get_hits(), 3, "hits 6, 6, 6; 2 misses on Q4")
    DamageRules.resolve_wounds_and_saves(result, dice)
    var model := result.model_results[0]
    _check_eq(model.wound_target, 4, "S4 vs T4: 4+")
    _check_eq(model.wound_rolls, [4, 1, 5], "one wound roll per hit")
    _check_eq(model.wounds, 2, "4 and 5 wound, natural 1 fails")
    _check_eq(model.save_target, 4, "3+ save with AP1: 4+")
    _check_eq(model.save_rolls, [4, 3], "one save roll per wound")
    _check_eq(model.saves, 1, "4 saves, 3 fails")
    _check_eq(result.get_unsaved_wounds(), 1, "one unsaved wound")
    _check(dice.rolls.is_empty(), "every scripted roll used")


func test_unsavable_wounds_roll_no_saves() -> void:
    var firing := _make_shooter(&"f", P1, Vector2(10.0, 10.0), [["Gun", _make_weapon(24.0, 1), Vector2.ZERO]])
    firing.data.models[0].weapon.strength = 3
    firing.data.models[0].weapon.armor_piercing = 3
    var target := _make_shooter(&"t", P2, Vector2(20.0, 10.0), [["T", null, Vector2.ZERO]])
    target.data.profile.toughness = 3
    target.data.profile.armor_save = 5
    var dice := ScriptedDice.new([6, 6])
    var result := ShootingRules.resolve(firing, target, LineOfSight.new(), dice)
    DamageRules.resolve_wounds_and_saves(result, dice)
    _check_eq(result.model_results[0].save_target, 8, "5+ with AP3 is 8+")
    _check_eq(result.model_results[0].save_rolls, [], "no save rolled when none can succeed")
    _check_eq(result.get_unsaved_wounds(), 1, "wound goes through")


func test_successful_saves_prevent_damage() -> void:
    var f := _shooting_fixture()
    _to_shooting(f)
    var p1: SquadState = f.battle.get_squad(&"p1_a")
    var p2: SquadState = f.battle.get_squad(&"p2_a")
    p2.data.profile.armor_save = 4
    f.shooting.dice = ScriptedDice.new([6, 6, 5])
    var results := []
    f.shooting.shot_resolved.connect(func(r): results.append(r))
    f.activation.activate(p1)
    f.shooting.order_shot(p1, p2)
    _check(not f.shooting.is_allocation_pending(), "saved wound needs no allocation")
    _check_eq(results[0].get_saves(), 1, "save made on a 5")
    _check_eq(p2.get_model(0).wounds_remaining, 1, "no damage taken")
    _check(not p2.lost_models_since_morale, "no loss recorded")
    _check(f.activation.has_activated(p1), "activation spent")
    _free_shooting_fixture(f)


func test_model_states_built_from_data() -> void:
    var line: SquadData = load("res://data/squads/p1_line_squad.tres")
    var state := SquadState.new(line, Vector2(12.0, 16.0))
    var models := state.get_models()
    _check_eq(models.size(), 4, "one model state per model")
    for i in models.size():
        _check_eq(models[i].model_id, i, "model %d id is its original index" % i)
        _check_eq(models[i].definition, line.models[i], "model %d references its definition" % i)
        _check_eq(models[i].wounds_remaining, line.profile.wounds, "model %d starts with the profile's W" % i)
        _check(not models[i].removed, "model %d alive" % i)
    _check_eq(state.get_leader(), models[0], "first model is the leader")
    _check_eq(state.get_model_position(models[1]), Vector2(12.0, 16.0) + line.models[1].formation_offset,
        "model position from the formation offset")
    print("        (the next error is expected)")
    models[2].model_id = 9
    _check_eq(models[2].model_id, 2, "model id cannot be reassigned")


func test_damage_tracking_leaves_resources_untouched() -> void:
    var squad := _make_shooter(&"s", P1, Vector2(5.0, 5.0), [["A", null, Vector2.ZERO], ["B", null, Vector2(1.0, 0.0)]],
        4, 2).data
    var first := SquadState.new(squad, Vector2(5.0, 5.0))
    var second := SquadState.new(squad, Vector2(5.0, 5.0))
    first.take_wound(1)
    _check_eq(first.get_model(1).wounds_remaining, 1, "damage tracked on the model state")
    _check_eq(second.get_model(1).wounds_remaining, 2, "another state built from the same data is unaffected")
    _check_eq(squad.profile.wounds, 2, "profile Wounds unchanged")
    _check_eq(squad.models.size(), 2, "data model list unchanged")
    _check_eq(squad.models[1].formation_offset, Vector2(1.0, 0.0), "definition unchanged")


func test_models_removed_at_zero_wounds() -> void:
    var state := _make_shooter(&"s", P1, Vector2(5.0, 5.0),
        [["A", null, Vector2.ZERO], ["B", null, Vector2(1.0, 0.0)], ["C", null, Vector2(2.0, 0.0)]], 4, 2)
    var changes := []
    state.models_changed.connect(func(s): changes.append(s.squad_id))
    _check(not state.take_wound(1), "first wound only damages")
    _check_eq(state.get_model(1).wounds_remaining, 1, "one wound left")
    _check(not state.lost_models_since_morale, "no model lost yet")
    _check(state.take_wound(1), "second wound removes the model")
    _check(state.get_model(1).removed, "model removed")
    _check_eq(state.get_model(1).wounds_remaining, 0, "no wounds left")
    _check_eq(state.get_model_count(), 2, "two living models")
    _check_eq(state.get_living_models().map(func(m): return m.model_id), [0, 2], "living models in original order")
    _check_eq(state.get_models().size(), 3, "removed models are kept, by id")
    _check(state.lost_models_since_morale, "loss recorded")
    _check_eq(changes.size(), 2, "models_changed emitted per wound")
    print("        (the next error is expected)")
    _check(not state.take_wound(1), "a removed model cannot take further wounds")


func test_allocation_rules() -> void:
    var state := _make_shooter(&"s", P2, Vector2(5.0, 5.0), [["A", null, Vector2.ZERO], ["B", null, Vector2(1.0, 0.0)]])
    _check_eq(DamageRules.validate_allocation(state, 0, 2), DamageRules.AllocationResult.OK, "leader allowed")
    _check_eq(DamageRules.validate_allocation(state, 1, 2), DamageRules.AllocationResult.OK, "any living model allowed")
    _check_eq(DamageRules.validate_allocation(state, 5, 2), DamageRules.AllocationResult.UNKNOWN_MODEL, "unknown id")
    _check_eq(DamageRules.validate_allocation(state, 0, 0), DamageRules.AllocationResult.NO_PENDING_WOUNDS, "nothing to allocate")
    state.take_wound(1)
    _check_eq(DamageRules.validate_allocation(state, 1, 1), DamageRules.AllocationResult.MODEL_REMOVED, "removed model refused")


## Shooter fixture whose target has `models` with `wounds` each, and a rifle
## that hits, wounds and goes unsaved on every roll of 6.
func _allocation_fixture(target_models: Array, wounds: int, attacks: int) -> Dictionary:
    var battle := BattleState.new()
    battle.add_squad(_make_shooter(&"p1_a", P1, Vector2(10.0, 10.0), [["Gun", _make_weapon(24.0, attacks), Vector2.ZERO]]))
    battle.add_squad(_make_shooter(&"p2_a", P2, Vector2(20.0, 10.0), target_models, 4, wounds))
    var tm := TurnManager.new()
    var activation := ActivationController.new()
    activation.bind(battle, tm)
    var shooting := ShootingController.new()
    shooting.bind(tm, activation, battle)
    var rolls: Array[int] = []
    for i in attacks * 2:
        rolls.append(6)
    shooting.dice = ScriptedDice.new(rolls)
    tm.start_game()
    var f := {"battle": battle, "tm": tm, "activation": activation, "shooting": shooting}
    _to_shooting(f)
    activation.activate(battle.get_squad(&"p1_a"))
    return f


func test_defender_allocates_wounds_freely() -> void:
    var f := _allocation_fixture([["A", null, Vector2.ZERO], ["B", null, Vector2(1.0, 0.0)], ["C", null, Vector2(0.0, 1.0)]], 2, 4)
    var shooting: ShootingController = f.shooting
    var target: SquadState = f.battle.get_squad(&"p2_a")
    var prompts := []
    shooting.allocation_required.connect(func(_r, left): prompts.append(left))
    shooting.order_shot(f.battle.get_squad(&"p1_a"), target)
    _check_eq(prompts, [4], "four unsaved wounds to allocate")
    _check_eq(shooting.allocate_wound(2), DamageRules.AllocationResult.OK, "wound on model C")
    _check_eq(target.get_model(2).wounds_remaining, 1, "C wounded")
    _check_eq(shooting.allocate_wound(0), DamageRules.AllocationResult.OK, "next wound elsewhere: no need to finish C")
    _check_eq(shooting.allocate_wound(2), DamageRules.AllocationResult.OK, "wounded C takes another wound")
    _check(target.get_model(2).removed, "C removed")
    _check_eq(shooting.allocate_wound(2), DamageRules.AllocationResult.MODEL_REMOVED, "removed C refused")
    _check_eq(shooting.get_wounds_left(), 1, "refused allocation keeps the wound pending")
    _check_eq(shooting.allocate_wound(1), DamageRules.AllocationResult.OK, "last wound on B")
    _check_eq(prompts, [4, 3, 2, 1], "prompted after each allocation")
    _check(not shooting.is_allocation_pending(), "all allocated")
    _check_eq([target.get_model(0).wounds_remaining, target.get_model(1).wounds_remaining], [1, 1], "A and B wounded")
    _check_eq(f.activation.active_squad, null, "shooter's activation ended")
    _free_shooting_fixture(f)


func test_allocation_holds_the_activation() -> void:
    var f := _allocation_fixture([["A", null, Vector2.ZERO], ["B", null, Vector2(1.0, 0.0)]], 1, 1)
    var shooter: SquadState = f.battle.get_squad(&"p1_a")
    var target: SquadState = f.battle.get_squad(&"p2_a")
    f.shooting.order_shot(shooter, target)
    _check(f.activation.locked, "activation locked while the defender allocates")
    _check(not f.activation.end_activation(), "activation cannot be ended early")
    _check_eq(f.shooting.order_shot(shooter, target), ShootingRules.OrderResult.ALLOCATION_PENDING, "no second shot")
    f.shooting.allocate_wound(1)
    _check(not f.activation.locked, "unlocked after allocation")
    _check(f.activation.has_activated(shooter), "activation spent")
    _check_eq(f.activation.get_active_player(), P2, "control passes to the defender")
    _free_shooting_fixture(f)


func test_leader_succession_keeps_positions_and_movement() -> void:
    var state := _make_shooter(&"s", P1, Vector2(10.0, 10.0),
        [["Leader", null, Vector2.ZERO], ["Second", null, Vector2(2.0, 0.0)], ["Third", null, Vector2(0.0, 3.0)]])
    _check_eq(state.get_leader().get_model_name(), "Leader", "first model leads")
    state.begin_turn_movement(6.0)
    state.apply_move(Vector2(13.0, 14.0), false)
    var second_world := state.get_model_position(state.get_model(1))
    var third_world := state.get_model_position(state.get_model(2))
    var moved := state.distance_moved
    state.take_wound(0)
    _check_eq(state.get_leader(), state.get_model(1), "next surviving model promoted")
    _check_eq(state.board_position, second_world, "anchor moves to the new leader")
    _check_eq(state.get_model(1).offset, Vector2.ZERO, "new leader sits on the anchor")
    _check_eq(state.get_model_position(state.get_model(1)), second_world, "new leader has not moved")
    _check_eq(state.get_model_position(state.get_model(2)), third_world, "other survivor has not moved")
    _check(is_equal_approx(state.distance_moved, moved), "distance moved this turn unchanged")
    _check_eq(state.turn_start_position, Vector2(12.0, 10.0), "turn start is where the new leader began the turn")
    _check_eq(state.movement_allowance, 6.0, "allowance unchanged")
    _check_eq(state.get_leader_profile().movement, 6.0, "movement read from the leader's profile")
    state.take_wound(1)
    _check_eq(state.get_leader(), state.get_model(2), "succession continues in original order")
    _check_eq(state.board_position, third_world, "anchor follows again")
    state.take_wound(2)
    _check(state.is_destroyed(), "no models left: destroyed")
    _check_eq(state.get_leader(), null, "no leader promoted")
    _check_eq(state.board_position, third_world, "anchor left where the last model fell")


func test_new_leader_governs_movement() -> void:
    var f := _activation_fixture(1, 1)
    var battle: BattleState = f.battle
    battle.remove_squad(&"p1_0")
    var squad := _make_shooter(&"p1_mover", P1, Vector2(10.0, 10.0),
        [["Leader", null, Vector2.ZERO], ["Second", null, Vector2(2.0, 0.0)]])
    battle.add_squad(squad)
    squad.take_wound(0)
    for i in 4:
        if f.tm.turn_number == 1:
            _complete_phase(f.activation, battle, f.tm)
    _check_eq(f.tm.turn_number, 2, "turn 2 (after the squad's Morale activation)")
    _check_eq(squad.movement_allowance, squad.get_leader_profile().movement, "allowance from the new leader's M")
    _check_eq(squad.turn_start_position, Vector2(12.0, 10.0), "turn starts at the new leader's position")
    f.activation.activate(squad)
    _check_eq(f.movement.order_move(squad, Vector2(18.5, 10.0)), MovementRules.Result.OUT_OF_RANGE, "beyond M is refused")
    _check_eq(f.movement.order_move(squad, Vector2(18.0, 10.0)), MovementRules.Result.OK, "6 from the new leader is allowed")
    _free_activation_fixture(f)


func test_destroyed_squad_removed_through_battle() -> void:
    var f := _allocation_fixture([["A", null, Vector2.ZERO], ["B", null, Vector2(1.0, 0.0)]], 1, 3)
    var battle: BattleState = f.battle
    var tm: TurnManager = f.tm
    var shooter: SquadState = battle.get_squad(&"p1_a")
    var target: SquadState = battle.get_squad(&"p2_a")
    var removed := []
    battle.squad_removed.connect(func(s): removed.append(s))
    var results := []
    f.shooting.shot_resolved.connect(func(r): results.append(r))
    _check_eq(tm.get_remaining_activations(P2), 1, "defender's activation still waiting")
    f.shooting.order_shot(shooter, target)
    f.shooting.allocate_wound(0)
    f.shooting.allocate_wound(1)
    _check_eq(removed, [target], "removed through BattleState")
    _check_eq(battle.get_squad(&"p2_a"), null, "gone from the battle")
    _check_eq(results[0].wasted_wounds, 1, "third wound had no model left")
    _check(results[0].target_destroyed, "result reports the destruction")
    _check_eq(results[0].get_casualties(), PackedStringArray(["A", "B"]), "casualties in order")
    _check_eq(f.activation.active_squad, null, "shooter completed its activation")
    _check_eq(tm.current_phase, Phase.ASSAULT, "defender's activation removed, so the phase ends")
    _free_shooting_fixture(f)


func test_morale_eligibility_follows_losses() -> void:
    var battle := BattleState.new()
    var hurt := _make_shooter(&"p1_hurt", P1, Vector2(5.0, 5.0), [["A", null, Vector2.ZERO], ["B", null, Vector2(1.0, 0.0)]])
    var fresh := _make_shooter(&"p2_fresh", P2, Vector2(30.0, 5.0), [["C", null, Vector2.ZERO]])
    battle.add_squad(hurt)
    battle.add_squad(fresh)
    var tm := TurnManager.new()
    var activation := ActivationController.new()
    activation.bind(battle, tm)
    tm.start_game()
    _check(not ActivationController.is_eligible(hurt, Phase.MORALE), "no losses: not eligible for Morale")
    hurt.take_wound(1)
    _check(ActivationController.is_eligible(hurt, Phase.MORALE), "lost a model: eligible for Morale")
    _check(not ActivationController.is_eligible(fresh, Phase.MORALE), "untouched squad: not eligible")
    for i in 3:
        _complete_phase(activation, battle, tm)
    _check(hurt.lost_models_since_morale, "flag kept through the turn until Morale")
    _check_eq(tm.current_phase, Phase.MORALE, "Morale phase held for the eligible squad")
    _check_eq(tm.get_remaining_activations(P1), 1, "one Morale activation for Player 1")
    _check_eq(tm.get_remaining_activations(P2), 0, "none for Player 2")
    _check_eq(activation.activate(fresh), ActivationController.Result.WRONG_PLAYER, "only Player 1 acts")
    activation.activate(hurt)
    _check(hurt.lost_models_since_morale, "flag kept during its Morale activation")
    activation.end_activation()
    _check(not hurt.lost_models_since_morale, "flag cleared once its Morale opportunity is resolved")
    _check_eq(tm.turn_number, 2, "turn advances after Morale")
    tm.free()
    activation.free()


func test_hud_shooting_report() -> void:
    var firing := _make_shooter(&"Shooters", P1, Vector2.ZERO, [])
    var target := _make_shooter(&"Targets", P2, Vector2.ZERO, [["T", null, Vector2.ZERO]])
    var result := ShootingResult.new()
    result.firing_squad = firing
    result.target_squad = target
    var gunner := ShootingResult.ModelResult.new()
    gunner.model_name = "Gunner"
    gunner.eligibility = ShootingRules.Eligibility.ELIGIBLE
    gunner.rolls = [5, 2]
    gunner.hits = 1
    gunner.wound_target = 3
    gunner.wound_rolls = [4]
    gunner.wounds = 1
    gunner.save_target = 7
    var idle := ShootingResult.ModelResult.new()
    idle.model_name = "Pistol"
    idle.eligibility = ShootingRules.Eligibility.OUT_OF_RANGE
    result.model_results = [gunner, idle]
    var allocation := ShootingResult.Allocation.new()
    allocation.model_name = "T"
    allocation.removed = true
    result.allocations = [allocation]
    result.target_destroyed = true
    _check_eq(HUD.format_shooting_result(result), "\n".join([
        "Shooters shot Targets",
        "Fired: 1  Unable: 1",
        "Attacks 2: 1 hit, 1 miss",
        "Wounds 1: 0 saved, 1 unsaved",
        "Gunner: 1/2 hit, 1 wnd (3+), 0 saved (7+, unsavable)",
        "Pistol: out of range",
        "Casualties: T",
        "Targets destroyed",
    ]), "full report")


func test_target_destroyed_in_main_scene() -> void:
    var main: Node = await _load_main()
    var layer: SquadLayer = main.get_node("GameBoard/Squads")
    var activation: ActivationController = main.get_node("ActivationController")
    var shooting: ShootingController = main.get_node("ShootingController")
    var selection: SelectionManager = main.get_node("SelectionManager")
    var info: SquadInfoPanel = main.get_node("HUD/SquadInfoPanel")
    var allocation: AllocationPanel = main.get_node("HUD/AllocationPanel")
    var feedback: Label = main.get_node("HUD/OrderFeedback")
    var tm: TurnManager = main.get_node("TurnManager")
    var line: SquadState = main.battle.get_squad(&"p1_line_squad")
    var raider: SquadState = main.battle.get_squad(&"p2_raider_squad")
    _complete_phase(activation, main.battle, tm)
    raider.board_position = Vector2(24.0, 16.0)
    # All six attacks hit (6s). Per model, wounds then saves: Sergeant, both
    # Troopers: wound 6, save 2 (fails 5+); Gunner: wounds 6, 6, 6, saves 2, 2, 2
    # (fail 6+). Six unsaved wounds against three Raiders.
    shooting.dice = ScriptedDice.new([6, 6, 6, 6, 6, 6, 6, 2, 6, 2, 6, 2, 6, 6, 6, 2, 2, 2])
    _click(layer.get_token(&"p2_raider_squad").global_position)
    _check_eq(selection.selected_squad, raider, "Raider Squad selected for inspection")
    _check(info.models_label.text.begins_with("Models 3/3"), "panel shows models remaining")
    _check_eq(info.wounds_value.text, "1", "W column is the profile characteristic")
    _check_eq(info.save_value.text, "5+", "armor save shown")
    activation.activate(line)
    shooting.order_shot(line, raider)
    _check(allocation.visible, "allocation requested")
    allocation.get_button(0).pressed.emit()
    _check(info.models_label.text.begins_with("Models 2/3"), "panel follows casualties")
    _check_eq(raider.get_leader().model_id, 1, "Raider promoted to leader")
    allocation.get_button(1).pressed.emit()
    allocation.get_button(2).pressed.emit()
    _check_eq(main.battle.get_squad(&"p2_raider_squad"), null, "Raider Squad destroyed")
    _check_eq(layer.get_token(&"p2_raider_squad"), null, "its token is gone")
    _check_eq(selection.selected_squad, null, "selection cleared")
    _check_eq(info.name_label.text, SquadInfoPanel.EMPTY_TEXT, "info panel cleared")
    _check(feedback.text.contains("Raider Squad destroyed"), "destruction reported")
    _check_eq(activation.active_squad, null, "Line Squad's activation completed")
    _check_eq(tm.current_phase, Phase.ASSAULT, "Player 2 has nothing left, so play moves on")
    main.queue_free()
    await process_frame


## A started game with `squads` and every controller bound (activation,
## movement and shooting).
func _battle_fixture(squads: Array) -> Dictionary:
    var battle := BattleState.new()
    for state in squads:
        battle.add_squad(state)
    var tm := TurnManager.new()
    var activation := ActivationController.new()
    activation.bind(battle, tm)
    var movement := MovementController.new()
    movement.bind(battle, tm, Vector2(48.0, 32.0))
    movement.activation = activation
    var shooting := ShootingController.new()
    shooting.bind(tm, activation, battle)
    tm.start_game()
    return {"battle": battle, "tm": tm, "activation": activation, "movement": movement, "shooting": shooting}


func _free_battle_fixture(f: Dictionary) -> void:
    f.tm.free()
    f.activation.free()
    f.movement.free()
    f.shooting.free()


func test_morale_flags_persist_until_each_squads_morale_activation() -> void:
    var hurt_p1 := _make_shooter(&"p1_a", P1, Vector2(5.0, 5.0), [["A", null, Vector2.ZERO], ["B", null, Vector2(1.0, 0.0)]])
    var hurt_p2 := _make_shooter(&"p2_b", P2, Vector2(30.0, 5.0), [["C", null, Vector2.ZERO], ["D", null, Vector2(1.0, 0.0)]])
    var fresh_p2 := _make_shooter(&"p2_c", P2, Vector2(30.0, 20.0), [["E", null, Vector2.ZERO]])
    var f := _battle_fixture([hurt_p1, hurt_p2, fresh_p2])
    var activation: ActivationController = f.activation
    var tm: TurnManager = f.tm
    hurt_p1.take_wound(1)
    _check(hurt_p1.lost_models_since_morale, "loss in the Movement phase sets the flag")
    _complete_phase(activation, f.battle, tm)
    _check_eq(tm.current_phase, Phase.SHOOTING, "in Shooting")
    _check(hurt_p1.lost_models_since_morale, "flag survives ending Movement activations, including its own")
    hurt_p2.take_wound(1)
    _complete_phase(activation, f.battle, tm)
    _complete_phase(activation, f.battle, tm)
    _check_eq(tm.current_phase, Phase.MORALE, "Morale phase held for the flagged squads")
    _check(hurt_p1.lost_models_since_morale and hurt_p2.lost_models_since_morale,
        "both flags survive Shooting and Assault activations")
    _check_eq([tm.get_remaining_activations(P1), tm.get_remaining_activations(P2)], [1, 1],
        "one Morale activation each; the unflagged squad gets none")
    _check_eq(activation.activate(fresh_p2), ActivationController.Result.NOT_ELIGIBLE, "unflagged squad not eligible")
    # Player 2 has more squads, so holds priority this turn and acts first.
    _check_eq(activation.get_active_player(), P2, "Player 2 has priority in Morale")
    _check_eq(activation.activate(hurt_p1), ActivationController.Result.WRONG_PLAYER, "p1_a waits for its turn")
    _check_eq(activation.activate(hurt_p2), ActivationController.Result.OK, "p2_b takes its Morale activation")
    _check(hurt_p2.lost_models_since_morale, "p2_b flag kept while its Morale activation is open")
    activation.end_activation()
    _check(not hurt_p2.lost_models_since_morale, "p2_b cleared after its own Morale activation")
    _check(hurt_p1.lost_models_since_morale, "p1_a still flagged: another squad's activation does not clear it")
    _check_eq(tm.current_phase, Phase.MORALE, "Morale continues for p1_a")
    _check_eq(activation.activate(hurt_p1), ActivationController.Result.OK, "p1_a takes its Morale activation")
    _check(hurt_p1.lost_models_since_morale, "p1_a flag kept while its Morale activation is open")
    activation.end_activation()
    _check(not hurt_p1.lost_models_since_morale, "p1_a cleared after its own Morale activation")
    _check_eq(tm.turn_number, 2, "turn advances only after both Morale opportunities")
    _free_battle_fixture(f)


func test_leader_succession_after_movement() -> void:
    var squad := _make_shooter(&"p1_m", P1, Vector2(10.0, 10.0),
        [["Leader", null, Vector2.ZERO], ["Second", null, Vector2(2.0, 0.0)], ["Third", null, Vector2(0.0, 3.0)]])
    var enemy := _make_shooter(&"p2_e", P2, Vector2(40.0, 25.0), [["E", null, Vector2.ZERO]])
    var f := _battle_fixture([squad, enemy])
    var movement: MovementController = f.movement
    f.activation.activate(squad)
    _check_eq(movement.order_move(squad, Vector2(13.0, 14.0)), MovementRules.Result.OK, "moved 5 of 6 this turn")
    var survivors_before := [squad.get_model_position(squad.get_model(1)), squad.get_model_position(squad.get_model(2))]
    var second_turn_start := Vector2(12.0, 10.0)
    squad.take_wound(0)
    _check_eq(squad.get_leader(), squad.get_model(1), "next model promoted")
    _check_eq(squad.board_position, survivors_before[0], "anchor at the new leader's current position")
    _check_eq([squad.get_model_position(squad.get_model(1)), squad.get_model_position(squad.get_model(2))],
        survivors_before, "survivors keep their world positions")
    _check_eq(squad.turn_start_position, second_turn_start, "turn start is where the new leader began this turn")
    _check(is_equal_approx(squad.distance_moved, 5.0), "distance moved still 5")
    _check(is_equal_approx(squad.get_remaining_movement(), 1.0), "1 movement left")
    _check(not squad.movement_complete, "movement not complete")
    _check_eq(squad.movement_allowance, 6.0, "allowance unchanged")
    _check_eq(movement.order_move(squad, second_turn_start + Vector2(0.0, 6.1)), MovementRules.Result.OUT_OF_RANGE,
        "6.1 from the new leader's turn start refused")
    _check_eq(movement.order_move(squad, second_turn_start + Vector2(0.0, 6.0)), MovementRules.Result.OK,
        "exactly 6 from the new leader's turn start allowed")
    _check(squad.movement_complete, "full allowance now used")
    f.activation.end_activation()
    for i in 4:
        if f.tm.turn_number == 1:
            _complete_phase(f.activation, f.battle, f.tm)
    _check_eq(f.tm.turn_number, 2, "turn 2")
    _check_eq(squad.turn_start_position, squad.board_position, "next turn starts from the new leader")
    _check_eq(squad.distance_moved, 0.0, "distance reset")
    _free_battle_fixture(f)


func test_destroyed_target_discards_unallocated_wounds() -> void:
    var gun := _make_weapon(30.0, 4)
    var shooter := _make_shooter(&"p1_s", P1, Vector2(10.0, 10.0), [["Gun", gun, Vector2.ZERO]])
    # A second Player 1 squad ties the squad count, so Player 1 keeps priority.
    var spare := _make_shooter(&"p1_spare", P1, Vector2(5.0, 30.0), [["S", null, Vector2.ZERO]])
    var target := _make_shooter(&"p2_t", P2, Vector2(20.0, 10.0), [["A", null, Vector2.ZERO], ["B", null, Vector2(1.0, 0.0)]])
    var other := _make_shooter(&"p2_o", P2, Vector2(40.0, 30.0), [["O", null, Vector2.ZERO]])
    var f := _battle_fixture([shooter, spare, target, other])
    var shooting: ShootingController = f.shooting
    var activation: ActivationController = f.activation
    var tm: TurnManager = f.tm
    # Four hits and four wounds (S0 vs T0 needs 2+); no armor saves.
    shooting.dice = ScriptedDice.new([6, 6, 6, 6, 6, 6, 6, 6])
    var resolved := []
    shooting.shot_resolved.connect(func(r): resolved.append(r))
    _complete_phase(activation, f.battle, tm)
    _check_eq(tm.current_phase, Phase.SHOOTING, "in Shooting")
    _check_eq(activation.activate(shooter), ActivationController.Result.OK, "Player 1 activates the shooter")
    _check_eq(shooting.order_shot(shooter, target), ShootingRules.OrderResult.OK, "shot accepted")
    _check_eq(shooting.get_wounds_left(), 4, "4 unsaved wounds against 2 models")
    shooting.allocate_wound(0)
    _check(shooting.is_allocation_pending() and activation.locked, "still pending after the first casualty")
    shooting.allocate_wound(1)
    _check(not shooting.is_allocation_pending(), "allocation ends when the last model falls")
    _check_eq(shooting.get_wounds_left(), 0, "no wounds left pending")
    _check_eq(resolved.size(), 1, "result reported once")
    _check_eq(resolved[0].wasted_wounds, 2, "remaining 2 wounds discarded")
    _check(resolved[0].target_destroyed, "result reports the destruction")
    _check_eq(f.battle.get_squad(&"p2_t"), null, "target removed through BattleState")
    _check(not activation.locked, "lock released")
    _check_eq(activation.active_squad, null, "shooter's activation ended")
    _check(activation.has_activated(shooter), "shooter recorded as activated this phase")
    _check_eq(tm.current_phase, Phase.SHOOTING, "phase continues: Player 2 still has a squad")
    _check_eq(activation.get_active_player(), P2, "control passes to Player 2")
    _check_eq(tm.get_remaining_activations(P2), 1, "only the destroyed squad's activation was removed")
    _check_eq(shooting.allocate_wound(1), DamageRules.AllocationResult.NO_PENDING_WOUNDS, "no further allocation")
    _check_eq(activation.activate(other), ActivationController.Result.OK, "Player 2 activates")
    _check(shooting.order_shot(other, shooter) == ShootingRules.OrderResult.OK, "next shooter can shoot normally")
    _free_battle_fixture(f)


func test_unit_profile_resource() -> void:
    var profile := UnitProfile.new()
    # Temporary test fixture values, not game balance data.
    profile.movement = 6.5
    profile.quality = 4
    profile.toughness = 3
    profile.wounds = 2
    profile.leadership = 7
    profile.armor_save = 4
    _check(profile is Resource, "UnitProfile is a Resource")
    _check_eq(profile.movement, 6.5, "movement")
    _check_eq(profile.quality, 4, "quality")
    _check_eq(profile.toughness, 3, "toughness")
    _check_eq(profile.wounds, 2, "wounds")
    _check_eq(profile.leadership, 7, "leadership")
    _check_eq(profile.armor_save, 4, "armor_save")
    _check_exported(profile, {
        "movement": TYPE_FLOAT, "quality": TYPE_INT, "toughness": TYPE_INT,
        "wounds": TYPE_INT, "leadership": TYPE_INT, "armor_save": TYPE_INT,
    })


func test_weapon_profile_resource() -> void:
    var weapon := WeaponProfile.new()
    # Temporary test fixture values, not game balance data.
    weapon.weapon_name = "Test Gun"
    weapon.range = 15.5
    weapon.attacks = 2
    weapon.strength = 5
    weapon.armor_piercing = 1
    _check(weapon is Resource, "WeaponProfile is a Resource")
    _check_eq(weapon.weapon_name, "Test Gun", "name")
    _check_eq(weapon.range, 15.5, "range")
    _check_eq(weapon.attacks, 2, "attacks")
    _check_eq(weapon.strength, 5, "strength")
    _check_eq(weapon.armor_piercing, 1, "armor_piercing")
    _check_exported(weapon, {"weapon_name": TYPE_STRING, "range": TYPE_FLOAT, "attacks": TYPE_INT,
        "strength": TYPE_INT, "armor_piercing": TYPE_INT})


func _check_exported(object: Object, expected: Dictionary) -> void:
    var found := {}
    for prop in object.get_property_list():
        if prop["usage"] & PROPERTY_USAGE_EDITOR and prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
            found[prop["name"]] = prop["type"]
    _check_eq(found, expected, "exported properties of %s" % object.get_script().get_global_name())


func test_main_scene_wiring() -> void:
    var main: Node = load("res://scenes/core/Main.tscn").instantiate()
    root.add_child(main)
    await process_frame
    _check(main.get_node_or_null("GameBoard") is GameBoard, "Main has GameBoard")
    _check(main.get_node_or_null("TurnManager") is TurnManager, "Main has TurnManager")
    _check(main.get_node_or_null("HUD") is HUD, "Main has HUD")
    var label := main.get_node_or_null("HUD/PhaseBanner/Label") as Label
    _check(label != null, "PhaseBanner label exists")
    if label:
        _check_eq(label.text, "Turn 1 - Movement", "banner text")
    var tm := main.get_node("TurnManager") as TurnManager
    var activation := main.get_node("ActivationController") as ActivationController
    for i in 3:
        _complete_phase(activation, main.battle, tm)
    if label:
        _check_eq(label.text, "Turn 2 - Movement", "banner text after a full turn (Morale has no tests yet)")
    main.queue_free()
    await process_frame
