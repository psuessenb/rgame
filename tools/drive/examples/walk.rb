# Input script for examples/walk.
#
# Walks a lap: right, down, left, up, then a diagonal. Physical ids, because the
# script stands where RGame::Core::Input does — the example never sees them, it
# reads :move_x and :move_y, which is the point of the InputMap in between.
#
# What the report should show: one `sprite` call per tick and one `text`, and a
# **first()/last() spread on the sprite row** — the first argument pair after the
# sheet name is the animation's row and column, so a walker that is animating
# and turning shows different rows there, while a stuck one shows the same twice.
#
# Nothing is clipped or translated: the hero is a child of the root drawing in
# window coordinates, with no camera and no WorldView anywhere. That is the
# floor this example establishes — every later example adds something to it.

idle 5
hold controls::KEY_RIGHT, 40
hold controls::KEY_DOWN, 30
hold controls::KEY_LEFT, 40
hold controls::KEY_UP, 30
hold [controls::KEY_RIGHT, controls::KEY_UP], 25 # diagonal: horizontal wins the facing
idle 10
