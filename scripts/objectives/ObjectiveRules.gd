extends RefCounted
class_name ObjectiveRules
## Fixed-objective rules as pure functions: placement validation, model
## eligibility, range, per-player presence and control. Nothing here changes
## game state.
##
## Rules (approved by the project lead):
##   - An objective is a point with a circular control radius. Its whole
##     control circle must lie on the battlefield; its centre may stand on any
##     terrain except inside an impassable area (boundary included); control
##     circles may touch but never overlap. Ids must be non-empty and unique,
##     radii positive. Any violation rejects the whole objective setup.
##   - Eligible: every living model of a squad on the battlefield that is not
##     Broken. Steady and Shaken squads count, engaged or not; round-long
##     engagement commitment, activation, regrouping and rallying are never
##     consulted. Every eligible model counts as one, whatever its profile.
##   - A model is in range when any part of its base is within the control
##     radius: the boundary counts, within ModelPlacement.CONTACT_TOLERANCE
##     (which only absorbs float rounding).
##   - Presence is each player's count of eligible models in range, summed
##     across all that player's squads.
##   - Control: nobody present is uncontrolled; equal non-zero presence is
##     contested; otherwise the player with more models controls it, by any
##     margin. Control is never remembered: it always follows current presence.

enum ControlState { UNCONTROLLED, CONTESTED, CONTROLLED }


## An objective's control as of now.
class Status:
    var control := ControlState.UNCONTROLLED
    ## The controlling player, or TurnManager.NO_PLAYER unless CONTROLLED.
    var player := TurnManager.NO_PLAYER
    ## Eligible models in range per player.
    var presence := {}


## Why `setups` cannot be used on a battlefield of `board_size` with `terrain`
## (none if null); empty when the whole set is valid.
static func placement_errors(setups: Array[ObjectiveSetup], board_size: Vector2,
        terrain: TerrainMap = null) -> PackedStringArray:
    var errors := PackedStringArray()
    var seen := {}
    for i in setups.size():
        var setup := setups[i]
        if setup == null:
            errors.append("objective setup #%d is empty" % i)
            continue
        var label := describe(setup, i)
        if setup.objective_id == &"":
            errors.append("%s has no id" % label)
        elif seen.has(setup.objective_id):
            errors.append("%s duplicates the id of objective setup #%d" % [label, seen[setup.objective_id]])
        else:
            seen[setup.objective_id] = i
        if not (setup.control_radius > 0.0 and is_finite(setup.control_radius)):
            errors.append("%s has an invalid control radius %s" % [label, setup.control_radius])
            continue
        if not ModelPlacement.base_on_board(setup.position, setup.control_radius, board_size):
            errors.append("%s: its control circle is not entirely on the battlefield" % label)
        if terrain and centre_in_impassable(setup.position, terrain):
            errors.append("%s: its centre is inside impassable terrain" % label)
    for i in setups.size():
        for j in range(i + 1, setups.size()):
            var a := setups[i]
            var b := setups[j]
            if a == null or b == null or not (a.control_radius > 0.0 and b.control_radius > 0.0):
                continue
            if ModelPlacement.bases_overlap(a.position, a.control_radius, b.position, b.control_radius):
                errors.append("%s and %s: control circles overlap" % [describe(a, i), describe(b, j)])
    return errors


## True if `point` is inside (or on the boundary of) any impassable area.
static func centre_in_impassable(point: Vector2, terrain: TerrainMap) -> bool:
    for placed in terrain.get_placed():
        if TerrainGeometry.contains_point(placed.impassable_area, point):
            return true
    return false


## True if `squad`'s living models may count toward objectives: it is not
## Broken.
static func is_eligible(squad: SquadState) -> bool:
    return squad != null and squad.morale_status != SquadState.MoraleStatus.BROKEN


## True if any part of a base of `base_radius` centred at `position` is within
## `objective`'s control radius (boundary inclusive).
static func in_range(objective: ObjectiveSetup, position: Vector2, base_radius: float) -> bool:
    return position.distance_to(objective.position) - base_radius \
        <= objective.control_radius + ModelPlacement.CONTACT_TOLERANCE


## Eligible living models within range of `objective`, per player, among every
## squad on `battle`: {TurnManager.PLAYER_ONE: n, TurnManager.PLAYER_TWO: m}.
static func presence(objective: ObjectiveSetup, battle: BattleState) -> Dictionary:
    var counts := {TurnManager.PLAYER_ONE: 0, TurnManager.PLAYER_TWO: 0}
    for squad in battle.get_squads():
        if not is_eligible(squad) or not counts.has(squad.get_player()):
            continue
        for model in squad.get_living_models():
            if in_range(objective, model.position, model.get_base_radius()):
                counts[squad.get_player()] += 1
    return counts


## Control from a presence count (see presence()).
static func resolve(counts: Dictionary) -> Status:
    var status := Status.new()
    status.presence = counts.duplicate()
    var p1: int = counts.get(TurnManager.PLAYER_ONE, 0)
    var p2: int = counts.get(TurnManager.PLAYER_TWO, 0)
    if p1 == 0 and p2 == 0:
        status.control = ControlState.UNCONTROLLED
    elif p1 == p2:
        status.control = ControlState.CONTESTED
    else:
        status.control = ControlState.CONTROLLED
        status.player = TurnManager.PLAYER_ONE if p1 > p2 else TurnManager.PLAYER_TWO
    return status


## `objective`'s control now, from the models on `battle`.
static func status_of(objective: ObjectiveSetup, battle: BattleState) -> Status:
    return resolve(presence(objective, battle))


## "objective setup #i 'Name' (id) at (x, y)" for messages.
static func describe(setup: ObjectiveSetup, index: int) -> String:
    return "objective setup #%d '%s' (%s) at (%.2f, %.2f)" % [index, setup.display_name, setup.objective_id,
        setup.position.x, setup.position.y]
