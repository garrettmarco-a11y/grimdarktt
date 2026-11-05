extends RefCounted
class_name VictoryRules
## Objective scoring and the game result, as pure functions. Control comes from
## ObjectiveRules; nothing here changes game state.
##
## Rules (approved by the project lead):
##   - Objectives are scored once per round, at the end of the Consolidation
##     phase: each objective a player controls then gives that player 1 VP.
##     Contested and uncontrolled objectives give nothing, and an objective
##     scores at most once per checkpoint.
##   - Scores accumulate across rounds; a checkpoint never changes an earlier
##     one.
##   - The scenario sets the round limit, a positive integer. After the last
##     round's checkpoint the higher total wins; equal totals are a draw. Only
##     the round limit ends the game: eliminating the opponent does not.

const POINTS_PER_OBJECTIVE := 1


## One scoring checkpoint.
class RoundScore:
    var round := 0
    ## One {"objective": ObjectiveSetup, "status": ObjectiveRules.Status} per
    ## objective, in scenario order.
    var entries: Array[Dictionary] = []
    ## VP gained at this checkpoint, per player.
    var points := {}
    ## Accumulated VP after this checkpoint, per player.
    var totals := {}


## The final result.
class GameResult:
    ## The winning player, or TurnManager.NO_PLAYER for a draw.
    var winner := TurnManager.NO_PLAYER
    var scores := {}
    var rounds := 0

    func is_draw() -> bool:
        return winner == TurnManager.NO_PLAYER


static func zero_scores() -> Dictionary:
    return {TurnManager.PLAYER_ONE: 0, TurnManager.PLAYER_TWO: 0}


## Why `limit` cannot be a scenario's round limit; empty if it can.
static func round_limit_errors(limit: int) -> PackedStringArray:
    var errors := PackedStringArray()
    if limit < 1:
        errors.append("the round limit must be a positive integer, not %d" % limit)
    return errors


## Scores `objectives` for `round` from the squads on `battle`, adding to
## `previous` totals (left unchanged).
static func score_checkpoint(objectives: Array[ObjectiveSetup], battle: BattleState, round: int,
        previous: Dictionary) -> RoundScore:
    var score := RoundScore.new()
    score.round = round
    score.points = zero_scores()
    var scored := {}
    for objective in objectives:
        if scored.has(objective.objective_id):
            continue  # at most once per checkpoint
        scored[objective.objective_id] = true
        var status := ObjectiveRules.status_of(objective, battle)
        score.entries.append({"objective": objective, "status": status})
        if status.control == ObjectiveRules.ControlState.CONTROLLED:
            score.points[status.player] += POINTS_PER_OBJECTIVE
    score.totals = zero_scores()
    for player in score.totals:
        score.totals[player] = previous.get(player, 0) + score.points[player]
    return score


## The result after the last round, `rounds`, from the accumulated `totals`.
static func final_result(totals: Dictionary, rounds: int) -> GameResult:
    var result := GameResult.new()
    result.scores = totals.duplicate()
    result.rounds = rounds
    var p1: int = totals.get(TurnManager.PLAYER_ONE, 0)
    var p2: int = totals.get(TurnManager.PLAYER_TWO, 0)
    if p1 > p2:
        result.winner = TurnManager.PLAYER_ONE
    elif p2 > p1:
        result.winner = TurnManager.PLAYER_TWO
    return result
