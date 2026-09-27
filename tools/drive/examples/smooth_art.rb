# Input script for examples/smooth_art.
#
# Watches the scene in a window, switches to fullscreen with F, and switches
# back before the run ends. A fullscreen window left behind on Xvfb, which has
# no window manager, holds the display and hangs the next run.
#
# What the report should show:
#
#   - **five `image` calls a frame, every one at x 0.0**, one for each figure.
#     Components::Sprite draws at its node, and the node's transform carries the
#     position, the tilt and the glide;
#   - **`rotated` on every frame but the first**, from about -14.3 to 14.3
#     degrees. The tilt starts upright;
#   - **`faded` on every frame but the first**, from 0.2 to 1.0. The fade starts
#     opaque;
#   - **one `scaled` a frame**, the `:letterbox` presentation: 1.0 in the
#     1280x720 window, and 0.625 (shown as 0.6) on the harness's 800x600 screen
#     once fullscreen;
#   - a clip of [0, 0, 1280, 720] before the first F, and [0, 75, 800, 450]
#     after it. The second F leaves fullscreen, but under Xvfb the window keeps
#     the screen's size, so the clip stays;
#   - six `text` calls and two `rect` calls a frame, and no missing translation.
#
# Nothing in the report depends on the filter: it records draw calls, not
# pixels. What `:linear` changes is seen by running the example twice.

idle 60
press controls::KEY_F # fullscreen
idle 60
press controls::KEY_F # and back to a window
idle 60
