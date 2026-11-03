extends RefCounted
class_name ChargeResult
## The outcome of one charge declaration that was accepted: the roll, how far
## the models could go, and whether contact with the declared target was made.

var charger: SquadState
var target: SquadState
## The single D6 rolled for the squad.
var roll := 0
## Movement + roll: the most each model could move.
var distance := 0.0
var succeeded := false
## Charging models that ended in base contact with the target squad.
var models_in_contact := 0
## The engagement the charge joined or created; null for a failed charge.
var engagement: EngagementTracker.Engagement
## model_id -> [start, end] for every charging model.
var paths := {}
