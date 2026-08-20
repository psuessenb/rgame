# Input script for examples/15_tiled_world.
#
# Physical ids, as the backend takes them. One long walk in each direction: the
# map is larger than the window, so a player that actually moves drags the
# tilemap's camera arguments with it — which is what the report's first()/last()
# columns show.

idle 5
hold controls::KEY_RIGHT, 60
hold controls::KEY_DOWN, 60
hold controls::KEY_LEFT, 30
hold controls::KEY_UP, 30
hold [controls::KEY_RIGHT, controls::KEY_DOWN], 40 # diagonal, both axes at once
idle 10
