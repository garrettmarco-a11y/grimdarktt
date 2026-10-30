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
    for i in 4:
        _play_phase(tm, 1, 1)
    if label:
        _check_eq(label.text, "Turn 2 - Movement", "banner text after a full turn")
    main.queue_free()
    await process_frame
