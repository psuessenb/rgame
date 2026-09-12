# Input script for examples/collision_tiles.
#
# Holds down and left, and nothing else, for the whole run. The hero starts ten
# tiles east of the fence's only gap and north of the fence, so a body that
# stopped dead on contact would stay there for two hundred ticks. Everything
# below follows from the fact that it does not.
#
# What the report should show:
#
#   - **the last `tilemap` call at camera (0.0, 160.0)**, which is the whole
#     acceptance test. 160 is the camera's southern clamp against a 640-tall map
#     in a 480-tall window, so it is only reached once the hero is south of the
#     fence — and the fence runs the full width of the map apart from columns 12
#     to 14. Holding a diagonal into a wall carried the hero along it, into the
#     gap, and through. A body that dropped the whole step instead of the blocked
#     half would still be standing against the fence with the camera where it
#     started;
#   - **the first `tilemap` call at camera (0.0, 0.0), and the second at
#     (72.0, 51.0).** The first frame is drawn before anything has updated, so the
#     camera is still at its origin; 72 and 51 are where `CameraFollow` puts it
#     once it has run once — the hero's start, less half the window, plus the
#     offset that centres the camera on the feet rather than the head;
#   - **translates spanning x −72..434 and y −160..394.** A translate carries the
#     camera as its opposite, so −72 and −160 are the two camera positions above,
#     the second of them the southern clamp. The positive extremes are things'
#     own places in the world: 394 is how far south the hero had walked by the end
#     of the budget, and 434 is the spiky ball, which never moves;
#   - **two `tilemap` calls per frame**, one per Tiled layer — the ground and the
#     obstacles — each drawn by its own `TileMapLayer` node inside the WorldView;
#   - **one `sprite` and one `rect` per frame**, the hero and its feet box, plus
#     one `circle` and two `line` calls for the spiky ball this script walks away
#     from. All of those hold their arguments for the whole run: a collision box
#     and a drawing are both stated in the node's own local space, so neither
#     varies with where the node is;
#   - **two clips per frame**, both the full window. One is the WorldView drawing
#     the world through the player's camera, the other the presentation's
#     letterbox. They coincide because this game has one player filling the
#     window; `examples/split_screen` is where they stop coinciding;
#   - **`text` ending on `"Lives: 3"`, and no audio.** This route never goes near
#     the ball, so nothing here costs a life — `collision_tiles_spike.rb` is the
#     script that does. Tile collision itself draws nothing and plays nothing: it
#     is a question asked of the grid between one position and the next.
#
# Nothing here needs a seed — the map is a file and the timestep is fixed, so two
# runs at one tick budget agree tick for tick.

idle 10
hold [controls::KEY_DOWN, controls::KEY_LEFT], 200 # into the fence, along it, through the gap
idle 30
