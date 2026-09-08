# Input script for examples/fullscreen.
#
# Toggles fullscreen on, off, and on again.
#
# What the report should show:
#
#   - **`line` and `rect` first()/last() arguments that change**. The border is
#     drawn from `view.width` / `view.height`, so the coordinates in those
#     columns are the window size: if they never move, the switch did not reach
#     the layout even though the window changed. That is the whole assertion
#     here, and it is the thing SDL makes easy to get wrong — a fullscreen
#     switch raises SDL_WINDOWEVENT_SIZE_CHANGED but *not* RESIZED, so an engine
#     listening only for the latter runs on at the old size;
#   - one `text` per frame, and no clips or translates: this is screen space.
#
# Under Xvfb with no window manager the window does not shrink back on the way
# out of fullscreen — there is nothing to restore it — so the second and third
# toggles may report the same size. The callback still fires; the window
# manager is what acts on it. Run it on a desktop to watch the border return.

idle 20
press controls::KEY_F # -> fullscreen
idle 40
press controls::KEY_F # -> windowed
idle 40
press controls::KEY_F # -> fullscreen again
idle 30
