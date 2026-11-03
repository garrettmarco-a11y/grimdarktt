extends PanelContainer
class_name TargetPanel
## Lets the player whose squad must declare its Assault-phase target choose
## it: one button per enemy squad of the engagement. Shown only while a
## declaration is awaited. It sends the choice to the EngagementController and
## never changes game state itself. Built in code; placed where the
## AllocationPanel sits, since the two are never needed at once.

var title_label: Label
var target_buttons: VBoxContainer

var _controller: EngagementController


func _init() -> void:
    visible = false
    offset_left = 4.0
    offset_top = 330.0
    offset_right = 152.0
    offset_bottom = 370.0
    var margin := MarginContainer.new()
    for side in ["left", "top", "right", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 8 if side in ["left", "right"] else 6)
    add_child(margin)
    var rows := VBoxContainer.new()
    margin.add_child(rows)
    title_label = Label.new()
    title_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
    title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rows.add_child(title_label)
    target_buttons = VBoxContainer.new()
    rows.add_child(target_buttons)


func bind(controller: EngagementController) -> void:
    _controller = controller
    controller.target_declaration_required.connect(func(_squad, _options): refresh())
    controller.target_declared.connect(func(_squad, _target): refresh())
    controller.strikes_rolled.connect(func(_engagement, _results): refresh())
    controller.assault_completed.connect(refresh)
    refresh()


func refresh() -> void:
    for child in target_buttons.get_children():
        target_buttons.remove_child(child)
        child.queue_free()
    var squad := _controller.get_declaring_squad() if _controller else null
    visible = squad != null
    if squad == null:
        return
    title_label.text = "Player %d: choose %s's target" % [squad.get_player(), squad.data.display_name]
    for target in _controller.get_target_options(squad):
        var button := Button.new()
        button.text = target.data.display_name
        button.set_meta("squad_id", target.squad_id)
        button.pressed.connect(_controller.declare_target.bind(squad, target))
        target_buttons.add_child(button)


## The button for enemy squad `squad_id`, or null.
func get_button(squad_id: StringName) -> Button:
    for button in target_buttons.get_children():
        if button.get_meta("squad_id") == squad_id:
            return button
    return null
