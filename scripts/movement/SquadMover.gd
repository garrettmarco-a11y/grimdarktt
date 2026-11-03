extends RefCounted
class_name SquadMover
## Resolves how a squad's models actually move: the leader goes to its
## destination and every follower heads for its formation slot, all advancing
## together in small steps so no model ever overlaps another, passes through
## one, or enters impassable terrain. Pure: it reads states and returns a plan;
## SquadState.apply_model_moves applies it.
##
## Rules (approved by the project lead):
##   - Models move simultaneously in steps of at most STEP. Within a step they
##     are taken in a fixed order: front to back along the squad's direction
##     of travel (projection of the current position onto that direction,
##     compared exactly), ties broken by model_id. Each is checked against
##     every other living base where it stands at that moment, own squad
##     included: a model that has not moved yet this step is an obstacle where
##     it stands, so no model moves into space on the assumption that its
##     occupant will move later. Paths are swept continuously, not just checked
##     at their ends. The result therefore depends only on positions, ids and
##     the order, never on the order models happen to be stored in.
##   - Each model pays for the path it actually travels, from its own
##     remaining allowance (difficult terrain doubled along its centre path,
##     unless `pay_terrain` is false, as for fall-back).
##   - A blocked model advances to exact computed contact (not into the
##     ModelPlacement.CONTACT_TOLERANCE band, which only absorbs float32
##     rounding). A follower then tries one slide along the obstacle for that
##     step; if that is blocked too it stops where it is. There is no
##     pathfinding and no model is ever teleported.
##   - A model that runs out of allowance stops where it is.

## Longest single step, in board units: well under a base radius, so nothing
## can pass through a base between checks (paths are also swept exactly).
const STEP := 0.2
## Smallest progress that counts as moving; a model that cannot make this
## much progress, straight or sliding, stops.
const MIN_PROGRESS := 0.001
## Allowance tolerance, as in MovementRules.
const EPSILON := 0.001
## Extra clearance a charging model keeps from enemy squads other than its
## target: just beyond base-contact range (ENGAGEMENT_CONTACT plus its
## rounding allowance), so a charge can never make incidental contact.
const CHARGE_KEEP_OUT := ModelPlacement.ENGAGEMENT_CONTACT + 3.0 * ModelPlacement.CONTACT_TOLERANCE
const BISECTION_STEPS := 32
const MAX_ITERATIONS := 5000


## How each model of a squad moved.
class Plan:
    extends RefCounted
    ## model_id -> [final position, cost paid]; every living model is listed.
    var moves := {}
    ## model_id -> true if the model reached its target.
    var reached := {}
    ## Living models that stopped before their target.
    var fell_short: Array[ModelState] = []
    var leader_reached := true

    func position_of(model: ModelState) -> Vector2:
        return moves[model.model_id][0]

    func cost_of(model: ModelState) -> float:
        return moves[model.model_id][1]


class _Mover:
    extends RefCounted
    var model: ModelState
    var position: Vector2
    var radius: float
    var target: Vector2
    var budget: float
    var cost := 0.0
    var may_slide := true
    ## Fall-back leader only: may cross the board edge (its target is the exit).
    var may_leave_board := false
    var stopped := false


## Plans a voluntary move: the leader of `squad` to `destination`, each
## follower to its formation slot relative to the leader's destination.
## `others` are the other squads on the battlefield (their living models are
## obstacles). The caller has validated the leader's own path.
## `observer`, if valid, is called after every single model advance with a
## Dictionary model_id -> current position (for tests).
static func plan_move(squad: SquadState, destination: Vector2, others: Array, terrain: TerrainMap,
        board_size: Vector2, observer := Callable()) -> Plan:
    var leader := squad.get_leader()
    var targets := {}
    if leader:
        for model in squad.get_living_models():
            targets[model.model_id] = destination + model.get_formation_slot() - leader.get_formation_slot()
    var direction := (destination - leader.position) if leader else Vector2.ZERO
    return _resolve(squad, targets, direction, others, terrain, board_size, true, squad.movement_allowance, 0.0, observer)


## Plans a forced move of every living model of `squad` by `distance` in
## `direction` (a unit vector), as for fall-back: difficult terrain is not
## paid for, everything physical still blocks, and each model may travel the
## full `distance` regardless of what it has already moved this turn.
## If `leader_exit` is a Vector2, the leader instead heads for that point on
## the board edge and may cross the edge to reach it (plan.leader_reached then
## means it left the battlefield); everyone else stays on the board.
static func plan_shift(squad: SquadState, direction: Vector2, distance: float, others: Array,
        terrain: TerrainMap, board_size: Vector2, observer := Callable(), leader_exit: Variant = null) -> Plan:
    var targets := {}
    for model in squad.get_living_models():
        targets[model.model_id] = model.position + direction * distance
    var leader := squad.get_leader()
    if leader_exit != null and leader:
        targets[leader.model_id] = leader_exit
    return _resolve(squad, targets, direction, others, terrain, board_size, false, -1.0, distance, observer,
        leader_exit != null)


## Plans a charge by `squad` against `target`: every living model heads for
## the target model nearest it when the charge begins (ChargeRules), moving at
## most `distance` and paying double inside difficult terrain, from a fresh
## budget that ignores Movement-phase use. Models stop on contact with the
## target; every model may slide once per step around an obstacle; impassable
## terrain, the board edge and every base still block, and enemy squads other
## than the target cannot be brought into base contact at all.
static func plan_charge(squad: SquadState, target: SquadState, distance: float, others: Array,
        terrain: TerrainMap, board_size: Vector2, observer := Callable()) -> Plan:
    var targets := {}
    var heading := Vector2.ZERO
    for model in squad.get_living_models():
        var aim := ChargeRules.nearest_target_model(model, target)
        targets[model.model_id] = aim.position if aim else model.position
    var leader := squad.get_leader()
    if leader:
        heading = targets[leader.model_id] - leader.position
    return _resolve(squad, targets, heading, others, terrain, board_size, true, -1.0, distance, observer, false, target)


## Plans consolidation for `squad` after an engagement: every model listed in
## `moving` heads for the living model of `target` nearest it (ChargeRules'
## nearest-model rule, fixed for the move) up to `distance`, ignoring
## difficult terrain; squad-mates not listed (those already in base contact)
## stay where they are and block like any base. Impassable terrain, the board
## edge and every base still block, every moving model may slide once per
## step, and models stop on contact. Contact with any enemy is allowed.
static func plan_consolidate(squad: SquadState, moving: Array, target: SquadState, distance: float, others: Array,
        terrain: TerrainMap, board_size: Vector2, observer := Callable()) -> Plan:
    var targets := {}
    var heading := Vector2.ZERO
    for model in moving:
        var aim := ChargeRules.nearest_target_model(model, target)
        targets[model.model_id] = aim.position if aim else model.position
        if heading == Vector2.ZERO and aim:
            heading = aim.position - model.position
    return _resolve(squad, targets, heading, others, terrain, board_size, false, -1.0, distance, observer, false, null, true)


static func _resolve(squad: SquadState, targets: Dictionary, direction: Vector2, others: Array,
        terrain: TerrainMap, board_size: Vector2, pay_terrain: bool, allowance: float,
        fixed_budget: float, observer: Callable, leader_leaves := false, charge_target: SquadState = null,
        all_slide := false) -> Plan:
    var leader := squad.get_leader()
    var movers: Array[_Mover] = []
    var models := squad.get_living_models()
    models.sort_custom(func(a: ModelState, b: ModelState) -> bool: return a.model_id < b.model_id)
    var obstacles := []
    for model in models:
        if not targets.has(model.model_id):
            # A squad-mate that is not moving stands where it is, as an obstacle.
            obstacles.append([model.position, model.get_base_radius()])
            continue
        var mover := _Mover.new()
        mover.model = model
        mover.position = model.position
        mover.radius = model.get_base_radius()
        mover.target = targets[model.model_id]
        mover.budget = maxf(allowance - model.movement_used, 0.0) if allowance >= 0.0 else fixed_budget
        mover.may_slide = model != leader or charge_target != null or all_slide
        mover.may_leave_board = leader_leaves and model == leader
        movers.append(mover)
    for other in others:
        if other == squad:
            continue
        # A charge may touch only its declared target: every other enemy squad
        # is kept out beyond base-contact range.
        var keep_out := 0.0
        if charge_target != null and other != charge_target and other.get_player() != squad.get_player():
            keep_out = CHARGE_KEEP_OUT
        for model in other.get_living_models():
            obstacles.append([model.position, model.get_base_radius() + keep_out])
    var heading := direction.normalized() if direction.length() > EPSILON else Vector2.ZERO
    for iteration in MAX_ITERATIONS:
        var active := movers.filter(func(m: _Mover) -> bool: return not m.stopped)
        if active.is_empty():
            break
        active.sort_custom(func(a: _Mover, b: _Mover) -> bool:
            var da := a.position.dot(heading)
            var db := b.position.dot(heading)
            if da != db:
                return da > db
            return a.model.model_id < b.model.model_id)
        for mover in active:
            _advance(mover, movers, obstacles, terrain, board_size, pay_terrain)
            if observer.is_valid():
                var positions := {}
                for m in movers:
                    positions[m.model.model_id] = m.position
                observer.call(positions)
    var plan := Plan.new()
    for mover in movers:
        plan.moves[mover.model.model_id] = [mover.position, mover.cost]
        var reached := mover.position.distance_to(mover.target) <= ModelPlacement.CONTACT_TOLERANCE
        plan.reached[mover.model.model_id] = reached
        if not reached:
            plan.fell_short.append(mover.model)
            if mover.model == leader:
                plan.leader_reached = false
    return plan


## Moves one model one step toward its target (or stops it).
static func _advance(mover: _Mover, movers: Array[_Mover], obstacles: Array, terrain: TerrainMap,
        board_size: Vector2, pay_terrain: bool) -> void:
    var to_target := mover.target - mover.position
    if to_target.length() <= ModelPlacement.CONTACT_TOLERANCE or mover.budget - mover.cost <= EPSILON:
        mover.stopped = true
        return
    var step := to_target.limit_length(STEP)
    var start := mover.position
    var start_cost := mover.cost
    _try(mover, step, movers, obstacles, terrain, board_size, pay_terrain)
    if mover.position.distance_to(start) >= MIN_PROGRESS or mover.position == mover.target:
        return
    if mover.may_slide:
        var normal := _blocking_normal(mover, step, movers, obstacles, terrain, board_size)
        if normal != Vector2.ZERO and step.dot(normal) < 0.0:
            var slide := step - normal * step.dot(normal)
            _try(mover, slide, movers, obstacles, terrain, board_size, pay_terrain)
            if mover.position.distance_to(start) >= MIN_PROGRESS:
                return
    # No real progress: stay exactly where it was rather than creep.
    mover.position = start
    mover.cost = start_cost
    mover.stopped = true


## Advances `mover` as far along `step` as its allowance and every obstacle
## allow, paying for the distance travelled.
static func _try(mover: _Mover, step: Vector2, movers: Array[_Mover], obstacles: Array, terrain: TerrainMap,
        board_size: Vector2, pay_terrain: bool) -> void:
    var from := mover.position
    var left := mover.budget - mover.cost
    var reach := 1.0
    if _cost(from, from + step, terrain, pay_terrain) > left:
        reach = _bisect(func(t: float) -> bool: return _cost(from, from + step * t, terrain, pay_terrain) <= left, 1.0)
    # A full step may end within the float-rounding band of contact (e.g.
    # formation-mates moving together); a blocked step is cut back to exact
    # computed contact, never into the band.
    if not _legal(mover, from, from + step * reach, movers, obstacles, terrain, board_size, ModelPlacement.CONTACT_TOLERANCE):
        reach = _bisect(func(t: float) -> bool: return _legal(mover, from, from + step * t, movers, obstacles, terrain, board_size, 0.0), reach)
    if reach <= 0.0:
        return
    var to := from + step * reach
    if reach >= 1.0 and from.distance_to(mover.target) <= step.length() + ModelPlacement.CONTACT_TOLERANCE:
        to = mover.target  # the final step lands exactly on the target
    mover.cost += _cost(from, to, terrain, pay_terrain)
    mover.position = to


## Largest t in [0, upper] for which `ok(t)` holds, assuming ok(0) and that
## ok is monotone (true up to some point, false beyond).
static func _bisect(ok: Callable, upper: float) -> float:
    var low := 0.0
    var high := upper
    for i in BISECTION_STEPS:
        var mid := (low + high) * 0.5
        if ok.call(mid):
            low = mid
        else:
            high = mid
    return low


static func _cost(from: Vector2, to: Vector2, terrain: TerrainMap, pay_terrain: bool) -> float:
    if pay_terrain and terrain:
        return terrain.movement_cost(from, to)
    return from.distance_to(to)


## True if `mover`'s base can travel straight from `from` to `to`, with
## `tolerance` allowed for float rounding at contact (0 for exact contact).
## Any path legal with tolerance 0 is legal with CONTACT_TOLERANCE, and any
## path legal with CONTACT_TOLERANCE ends where ModelPlacement finds no
## overlap: movement and validation agree by construction.
static func _legal(mover: _Mover, from: Vector2, to: Vector2, movers: Array[_Mover], obstacles: Array,
        terrain: TerrainMap, board_size: Vector2, tolerance: float) -> bool:
    if not mover.may_leave_board and not ModelPlacement.base_on_board(to, mover.radius, board_size, tolerance):
        return false
    if terrain and terrain.base_crosses_impassable(from, to, mover.radius, tolerance):
        return false
    for other in movers:
        if other != mover and _path_hits(from, to, mover.radius, other.position, other.radius, tolerance):
            return false
    for obstacle in obstacles:
        if _path_hits(from, to, mover.radius, obstacle[0], obstacle[1], tolerance):
            return false
    return true


## True if the path from `from` to `to` brings the base into overlap with the
## base at `other`. A base that starts closer than contact (rounding at
## contact, or an invalid layout) may move along or away from it, never
## closer, and never below the shared contact tolerance.
static func _path_hits(from: Vector2, to: Vector2, radius: float, other: Vector2, other_radius: float,
        tolerance: float) -> bool:
    var contact := radius + other_radius - tolerance
    if from.distance_to(other) < contact:
        return to.distance_to(other) < from.distance_to(other) \
            or to.distance_to(other) < radius + other_radius - ModelPlacement.CONTACT_TOLERANCE
    return ModelPlacement.path_hits_base(from, to, radius, other, other_radius, tolerance)


## Outward normal of whatever blocks `mover`'s `step`: another base, impassable
## terrain or the board edge. Vector2.ZERO if nothing identifiable blocks it.
static func _blocking_normal(mover: _Mover, step: Vector2, movers: Array[_Mover], obstacles: Array,
        terrain: TerrainMap, board_size: Vector2) -> Vector2:
    var probe := mover.position + step
    var best := INF
    var normal := Vector2.ZERO
    var bases := []
    for other in movers:
        if other != mover:
            bases.append([other.position, other.radius])
    bases.append_array(obstacles)
    var best_at := Vector2.ZERO
    for base in bases:
        var gap: float = probe.distance_to(base[0]) - mover.radius - base[1]
        if not _path_hits(mover.position, probe, mover.radius, base[0], base[1], 0.0):
            continue
        # Nearest blocker wins; exact ties go to the lower x, then y, so the
        # choice never depends on the order bases are listed in.
        var at: Vector2 = base[0]
        if gap < best or (gap == best and (at.x < best_at.x or (at.x == best_at.x and at.y < best_at.y))):
            best = gap
            best_at = at
            normal = (mover.position - at).normalized()
    if normal != Vector2.ZERO:
        return normal
    if terrain and terrain.base_crosses_impassable(mover.position, probe, mover.radius, 0.0):
        var nearest = terrain.nearest_impassable_point(mover.position)
        if nearest != null:
            return (mover.position - nearest).normalized()
    if not mover.may_leave_board and not ModelPlacement.base_on_board(probe, mover.radius, board_size, 0.0):
        if probe.x < mover.radius:
            return Vector2.RIGHT
        if probe.y < mover.radius:
            return Vector2.DOWN
        if probe.x > board_size.x - mover.radius:
            return Vector2.LEFT
        return Vector2.UP
    return Vector2.ZERO
