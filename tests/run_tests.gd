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
        await call(method_name)
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


func test_unit_profile_resource() -> void:
    var profile := UnitProfile.new()
    # Temporary test fixture values, not game balance data.
    profile.movement = 6.5
    profile.quality = 4
    profile.toughness = 3
    profile.wounds = 2
    profile.leadership = 7
    _check(profile is Resource, "UnitProfile is a Resource")
    _check_eq(profile.movement, 6.5, "movement")
    _check_eq(profile.quality, 4, "quality")
    _check_eq(profile.toughness, 3, "toughness")
    _check_eq(profile.wounds, 2, "wounds")
    _check_eq(profile.leadership, 7, "leadership")
    _check_exported(profile, {
        "movement": TYPE_FLOAT, "quality": TYPE_INT, "toughness": TYPE_INT,
        "wounds": TYPE_INT, "leadership": TYPE_INT,
    })


func test_weapon_profile_resource() -> void:
    var weapon := WeaponProfile.new()
    # Temporary test fixture values, not game balance data.
    weapon.strength = 5
    weapon.armor_value = 3
    weapon.armor_piercing = 1
    _check(weapon is Resource, "WeaponProfile is a Resource")
    _check_eq(weapon.strength, 5, "strength")
    _check_eq(weapon.armor_value, 3, "armor_value")
    _check_eq(weapon.armor_piercing, 1, "armor_piercing")
    _check_exported(weapon, {"strength": TYPE_INT, "armor_value": TYPE_INT, "armor_piercing": TYPE_INT})


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
