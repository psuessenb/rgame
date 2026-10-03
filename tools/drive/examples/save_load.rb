# Input script for examples/save_load.
#
# Walks the dog, saves, walks somewhere else, loads it back, then discards the
# save. Nothing here can check what landed on disk — the harness reports draw
# calls, not files — so what it proves is that the whole path runs without
# raising and that loading visibly moves the dog.
#
# What the report should show:
#
#   - **`circle` last() is the dog, back near where the save was taken**, though
#     the script walks it away after saving. The flock is drawn first, so first()
#     is a sheep: radius 9 to the dog's 11;
#   - a steady 9 `circle` calls per frame — one dog, eight sheep — and three
#     `text`: help, keys and status. The flock is a fixed size, which is the
#     assumption that lets an array index stand in for identity;
#   - **one clip per frame, at the logical 640x480.** That is the presentation,
#     which every game pushes under the default `:letterbox`; nothing in this
#     example clips anything;
#   - **a translate per node per frame** — the dog and the eight sheep — spanning
#     the pasture, plus the presentation's own at the origin. The nodes push
#     these on the way down even though the scene draws every circle itself from
#     their coordinates: a transform is pushed because a node was *reached*, not
#     because it drew anything.
#
# **Run the example twice by hand to see the interesting half.** Press F5 in the
# first run, and it leaves a save in the platform's data directory. The second
# run loads it before the first frame and starts the dog where the first run
# saved it. That is the half no driven run can show, and the reason the example
# prints its status on screen.
#
# The harness gives each run a fresh save directory and removes it afterwards.
# So a driven run starts with no save, and does not write into the home
# directory of whoever is running it:
#
#   ruby tools/drive_test_project.rb examples/save_load/main.rb
#
# The script ends by discarding the save, and with `--texts` the report lists
# "save deleted" as the last status. A run given its own `RGAME_SAVE_DIR` keeps
# that directory but not the save, so the next run with it starts fresh too.

ticks 200

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
