# Actor-blocking script for test_projects/tiled_world.
#
# The scenario the actor blocker exists for: **a player walking into a villager
# and being stopped by them, the way a fence stops them.**
#
# The walker starts at the map centre (960, 720) and the first villager stands
# still at (880, 672). Up for 26 ticks to line the two feet boxes up, then left
# into the villager, holding the key down long after the walker has stopped.
#
# What the report should show: the camera track stopping short. With the walker
# declaring `blocked_by: %i[tiles hero npc]` it halts at x 900 and the last
# `tilemap` call is at camera x 588; with only `:tiles` declared it walks
# straight through the villager to x 820, where a wall stops it, and the last
# `tilemap` call is at 508. The distinct translate count falls from 777 to 697
# for the same reason — the camera visits fewer places.

idle 5
hold controls::KEY_UP, 26
hold controls::KEY_LEFT, 70
idle 39
