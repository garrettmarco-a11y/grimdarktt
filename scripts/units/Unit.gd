extends Node2D
class_name Unit
## A single model on the battlefield.
##
## Stats come from `profile`. Activation happens per squad (see TurnManager),
## never per individual model.

@export var profile: UnitProfile
