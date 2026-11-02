extends Resource
class_name TerrainSetup
## One placed terrain piece: which piece, and where it stands on the battlefield.

@export var piece: TerrainPiece
## Placement of the piece's local origin, in board units.
@export var position := Vector2.ZERO
## Rotation about the piece's local origin, in degrees.
@export var rotation_degrees := 0.0
