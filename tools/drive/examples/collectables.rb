# Input script for examples/collectables.
#
# Walks right into the chest, taking the two coins on the way, opens it, and
# collects two of the three it spills. Physical ids, because the script stands
# where RGame::Core::Input does: the example reads :move_x, :move_y and
# :interact, which is what the InputMap in between is for.
#
# What the report should show, on `--texts`:
#
#   - **"Coins: 0" through "Coins: 4", with no number skipped** — at ticks 0,
#     43, 87, 155 and 216. Each step is one contact, and the counter is an
#     Engine::Text rendered again only when the count changes, so a missing
#     number would mean a coin taken twice or not at all.
#   - **4 sounds**, one per coin. The chest makes none.
#   - **"Press E" from tick 121**, and for 17 frames only: the prompt is drawn
#     from `interactor.target`, which the walk fills when the chest stops the
#     hero, and the room stops drawing it the moment the chest is open.
#   - **1287 `circle` calls.** That is the coin count integrated over the run,
#     and it is the one number that says the chest spilled: six coins fall to
#     four by tick 137, rise to seven, and fall to five.
#
# `idle 2` sits between arriving and pressing because an Interactor acts on the
# target the last update chose. The walk right is 130 ticks for 224 pixels of
# travel, which overshoots on purpose: the chest blocks, so the hero arrives
# flush against it whatever the count.

idle 5
hold controls::KEY_RIGHT, 130   # the coins at 150 and 230, then flush against the chest
idle 2
press controls::KEY_E           # it opens and spills three
idle 5
hold controls::KEY_LEFT, 22     # the one it spilled to the left
hold controls::KEY_UP, 30
hold controls::KEY_RIGHT, 25    # and the one above it
idle 20
