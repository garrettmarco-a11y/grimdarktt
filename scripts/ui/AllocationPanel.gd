extends PanelContainer
class_name AllocationPanel
## Lets the defender allocate each unsaved wound: one button per living model
## in the target squad. Shown only while wounds await allocation. It sends each
## choice to the ShootingController and never changes game state itself.

@onready var title_label: Label = %TitleLabel
@onready var model_buttons: VBoxContainer = %ModelButtons

var _shooting: ShootingController


func bind(shooting: ShootingController) -> void:
    _shooting = shooting
    shooting.allocation_required.connect(func(_result, _left): refresh())
    shooting.shot_resolved.connect(func(_result): refresh())
    refresh()


func refresh() -> void:
    for child in model_buttons.get_children():
        model_buttons.remove_child(child)
        child.queue_free()
    var result := _shooting.get_pending_result() if _shooting else null
    visible = result != null
    if result == null:
        return
    var target := result.target_squad
    var left := _shooting.get_wounds_left()
    title_label.text = "Player %d: allocate %d wound%s to %s" % [target.get_player(), left,
        "" if left == 1 else "s", target.data.display_name]
    for model in target.get_living_models():
        var button := Button.new()
        button.text = "%s (%d W)" % [model.get_model_name(), model.wounds_remaining]
        button.set_meta("model_id", model.model_id)
        button.pressed.connect(_shooting.allocate_wound.bind(model.model_id))
        model_buttons.add_child(button)


## The button for model `model_id`, or null.
func get_button(model_id: int) -> Button:
    for button in model_buttons.get_children():
        if button.get_meta("model_id") == model_id:
            return button
    return null
