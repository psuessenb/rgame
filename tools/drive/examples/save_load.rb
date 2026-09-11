# Input script for examples/save_load.
#
# Walks the dog, saves, walks somewhere else, loads it back, then discards the
# save. Nothing here can check what landed on disk — the harness reports draw
# calls, not files — so what it proves is that the whole path runs without
# raising and that loading visibly moves the dog.
#
# What the report should show:
#
#   - **`circle` first() and last() with different dog coordinates**, and the
#     last one back near where the save was taken. The dog is drawn last, so it
#     is the `circle` row's last() argument;
#   - a steady 9 `circle` calls per frame — one dog, eight sheep — and two
#     `text`. The flock is a fixed size, which is the assumption that lets an
#     array index stand in for identity;
#   - **one clip per frame, at the logical 640x480.** That is the presentation,
#     which every game pushes under the default `:letterbox`; nothing in this
#     example clips anything;
#   - **a translate per node per frame** — the dog and the eight sheep — spanning
#     the pasture, plus the presentation's own at the origin. The nodes push
#     these on the way down even though the scene draws every circle itself from
#     their coordinates: a transform is pushed because a node was *reached*, not
#     because it drew anything.
#
# **Run it twice to see the interesting half.** The first run leaves a save in
# the platform's data directory; the second loads it before the first frame and
# starts the dog where the first run left it. That is the half a single driven
# run cannot show, and the reason the example prints its status on screen.
#
# It ends by discarding the save, so a driven run leaves nothing behind for the
# next one to find — which would otherwise make this script's own output depend
# on whether it had been run before.
#
# Set `RGAME_SAVE_DIR` to somewhere disposable when driving this, so the run
# does not write into the home directory of whoever is running it:
#
#   RGAME_SAVE_DIR=/tmp/saves ruby tools/drive_test_project.rb \
#     examples/save_load/main.rb --ticks 200

idle 10
hold controls::KEY_RIGHT, 30
hold controls::KEY_DOWN, 20
press controls::KEY_F5 # save, with the dog down and to the right

hold controls::KEY_LEFT, 45 # walk somewhere else entirely
hold controls::KEY_UP, 25
idle 10

press controls::KEY_F9 # load: the dog jumps back to where it was saved
idle 25

press controls::KEY_DELETE # leave no save behind for the next run
idle 10
