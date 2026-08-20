# Input script for examples/15_tiled_world.
#
# One long walk in each direction. The point is the camera: the map is larger
# than the window, so a player that actually moves drags the tilemap's camera
# arguments with it — which is what the report's first()/last() columns show.

idle 5
hold :right, 60
hold :down,  60
hold :left,  30
hold :up,    30
hold %i[right down], 40 # diagonal, exercising both axes at once
idle 10
