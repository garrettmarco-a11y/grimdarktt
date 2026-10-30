extends Resource
class_name SquadSetup
## Starting configuration for one squad in a battle: which squad, and where it
## begins. Used once to create the squad's SquadState.

@export var squad: SquadData
## Starting position in board distance units.
@export var start_position := Vector2.ZERO
