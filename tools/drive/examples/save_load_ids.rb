# Input script for examples/save_load_ids.
#
# Shears two sheep out of the middle of the flock, adds a new one, points the
# dog at it, saves, then wanders off and loads it back.
#
# Set `RGAME_SAVE_DIR` when driving this, so the run does not write into the
# home directory of whoever is running it:
#
#   RGAME_SAVE_DIR=/tmp/saves ruby tools/drive_test_project.rb \
#     examples/save_load_ids/main.rb --ticks 200
#
# What the report should show:
#
#   - the `text` row's last() argument is a sheep's **id label**, and the ids
#     that survive shearing keep their numbers. Sheep are drawn with their id
#     beside them, so the labels in the report are the flock's actual names;
#   - a `line` per frame — the tether from dog to target — and one `circle` per
#     sheep plus one for the dog, so the circle count drops as sheep are sheared
#     and rises again when one is added;
#   - no clips and no translates: screen space, no camera.
#
# **What a single run cannot show is the point of the example.** Whether the dog
# is still watching the *same numbered* sheep after a load is a fact about two
# processes, and this harness runs one. Run it twice against the same
# `RGAME_SAVE_DIR` and read the second run's status line, or check the ids in
# the JSON by hand.

idle 15
press controls::KEY_TAB   # target sheep 2
idle 5
press controls::KEY_SPACE # shear it — 2 leaves, 3..5 keep their numbers
idle 10
press controls::KEY_TAB
press controls::KEY_SPACE # and another out of the middle
idle 10

press controls::KEY_N     # a new sheep, with the next id rather than a reused one
idle 10
press controls::KEY_TAB   # point the dog somewhere specific before saving
idle 5
press controls::KEY_F5    # save: flock, ids, target id, and the allocator

hold controls::KEY_RIGHT, 40 # walk away, so the load visibly moves the dog back
hold controls::KEY_UP, 20
idle 5
press controls::KEY_F9
idle 30

press controls::KEY_DELETE # leave nothing behind for the next run
idle 10
