# Input script for examples/quests_and_dialogue.
#
# Plays the quest through. It talks to the smith and takes the work, picks up
# the hammer, walks into the signpost, and saves. Then it hands the hammer
# over, buys the lantern, opens the log, and loads the save. A third talk
# finds the quest as the save left it. Run it with --texts:
#
#   ruby tools/drive_test_project.rb examples/quests_and_dialogue/main.rb --ticks 1700 --texts
#
# What the report should show under "texts drawn":
#
#   - **"Any work going?" in the first talk only**, 23 frames from tick 143.
#     It is `once: true` on a named dialogue, so the save keeps it hidden too;
#   - **the quest's stage moving on the HUD**: "not heard of it" to tick 165,
#     "somewhere by the well" from 166, "in hand" from 407, when the hero walks
#     over the hammer, and "returned" from 883;
#   - **the signpost's line once**, 22 frames from tick 612. The hero walks
#     into it and stands on it, and `on_hit` does not fire again;
#   - **"I found your hammer." first drawn at tick 860**, in the second talk;
#   - **"I'll take a lantern." first drawn at tick 948**, once the reward put
#     the gold at 60. "Gold: 20", then "Gold: 60" from 883, "Gold: 10" from 971;
#   - **the log's lines from tick 1058**, "Smith: " before each of the smith's,
#     and the responses' labels alone;
#   - **after F9, "Loaded" from tick 1166**, the gold back at 20 and the stage
#     at "in hand". The third talk offers the hammer again and, after it, the
#     lantern, and still not the work;
#   - nothing under "missing or mismatched keys".
#
# Under "draw calls", **195 `circle` calls**: the hero's lantern, from the
# purchase at tick 971 until the load took it away at 1166.
#
# The walks are timed at 150 pixels a second, 2.5 a tick. The hero is paused
# during a conversation, so a direction still held when one starts walks on
# once it ends.

# --- the first talk: the work --------------------------------------------
idle 10
hold controls::KEY_UP, 100    # up to the smith, stopped by them
idle 10
press controls::KEY_RETURN    # talk
idle 20
press controls::KEY_RETURN    # the rest of the greeting, and its responses
idle 20
press controls::KEY_RETURN    # "Any work going?" — the quest starts
idle 20
press controls::KEY_RETURN    # the rest of the answer
idle 20
press controls::KEY_RETURN    # back to the greeting
idle 20
press controls::KEY_RETURN    # the rest of it: "Goodbye." is the only response left
idle 20
press controls::KEY_RETURN    # "Goodbye."
idle 20

# --- the hammer, then the signpost ----------------------------------------
hold controls::KEY_DOWN, 55   # down, level with the hammer
hold controls::KEY_RIGHT, 90  # over the hammer: picked up
hold controls::KEY_LEFT, 172  # all the way west, into the signpost
idle 20
press controls::KEY_RETURN    # the rest of the sign
idle 20
press controls::KEY_RETURN    # done reading
idle 20

# --- save, off the post ---------------------------------------------------
hold controls::KEY_UP, 30
idle 10
press controls::KEY_F5
idle 10

# --- the second talk: the reward, the lantern and the log ------------------
hold controls::KEY_UP, 30
hold controls::KEY_RIGHT, 90  # east along the forge, stopped by the smith
idle 10
press controls::KEY_RETURN    # talk
idle 20
press controls::KEY_RETURN    # the rest of the greeting
idle 20
press controls::KEY_RETURN    # "I found your hammer."
idle 20
press controls::KEY_RETURN    # the rest of the thanks
idle 20
press controls::KEY_RETURN    # back to the greeting
idle 20
press controls::KEY_RETURN    # the rest of it: now "I'll take a lantern." is there
idle 20
press controls::KEY_RETURN    # buy it
idle 20
press controls::KEY_RETURN    # the rest of that
idle 20
press controls::KEY_RETURN    # back to the greeting
idle 20
press controls::KEY_RETURN    # the rest of it
idle 20
press controls::KEY_L         # the log, on its last page
idle 30
press controls::KEY_UP        # a page back
idle 30
press controls::KEY_L         # closed again
idle 20
press controls::KEY_RETURN    # "Goodbye."
idle 20

# --- load ------------------------------------------------------------------
press controls::KEY_F9
idle 20

# --- the third talk: the save held the quest and the smith's visits --------
hold controls::KEY_UP, 30
hold controls::KEY_RIGHT, 90
idle 10
press controls::KEY_RETURN
idle 20
press controls::KEY_RETURN
idle 20
press controls::KEY_RETURN    # "I found your hammer." again
idle 20
press controls::KEY_RETURN    # the rest of the thanks
idle 20
press controls::KEY_RETURN    # back to the greeting
idle 20
press controls::KEY_RETURN    # the rest of it: the lantern is for sale again
idle 20
press controls::KEY_DOWN
idle 10
press controls::KEY_RETURN    # "Goodbye."
idle 40
