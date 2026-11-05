extends Resource
class_name ObjectiveSetup
## One fixed objective of a scenario: its identity, where it stands and its
## control radius. Static definition only, in board units; who controls it is
## computed from current model positions by ObjectiveRules, never stored here.

## Starting control radius, in board units.
const DEFAULT_CONTROL_RADIUS := 3.0

## Stable, unique identifier (e.g. &"objective_a").
@export var objective_id: StringName = &""
## Shown on the battlefield (e.g. "A").
@export var display_name := ""
## Centre of the objective, in board units.
@export var position := Vector2.ZERO
## Radius of the circular control area around `position`, in board units.
@export var control_radius := DEFAULT_CONTROL_RADIUS
