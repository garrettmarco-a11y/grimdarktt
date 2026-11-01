extends RefCounted
class_name MoraleResult
## One morale test and its consequences, for the HUD and tests.

enum Kind { ORDINARY, RALLY, ASSAULT_LOSS }

var squad: SquadState
var kind := Kind.ORDINARY
var dice: Array[int] = []
var total := 0
var base_leadership := 0
## Leadership after the below-half-strength modifier.
var leadership := 0
var below_half := false
var passed := false
var status_before := SquadState.MoraleStatus.STEADY
var status_after := SquadState.MoraleStatus.STEADY
var fell_back := false
var fallback_edge := MoraleRules.Edge.WEST
var fallback_from := Vector2.ZERO
var fallback_to := Vector2.ZERO
## True if the fall-back took the squad off the battlefield.
var removed := false
