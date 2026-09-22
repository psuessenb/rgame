# Input script for examples/dialogue.
#
# Begins the dialogue, asks every question, takes the news branch both ways,
# leaves, and begins a second dialogue. Run it with --texts; the draw calls
# alone cannot show which line was on screen when:
#
#   ruby tools/drive_test_project.rb examples/dialogue/main.rb --ticks 1100 --texts
#
# What the report should show under "texts drawn":
#
#   - **the prompt for 83 frames**: 21 before the first dialogue and 62
#     between its end and the second. It is never drawn while a box is open;
#   - **the greeting typing out twice**, each prefix drawn in both dialogues,
#     "E" from tick 22. The Enter that began the first dialogue skipped
#     nothing: the box waits for Enter to be let go;
#   - **the hub's question and its four responses drawn from tick 185**, on
#     each of the hub's four visits;
#   - **every answer**: the room's two lines from tick 237, the road's four
#     lines over two pages, its last line alone from tick 399, the news and
#     its two responses, and the wolves;
#   - **"I'd rather not hear it." leading straight back**: no line between the
#     news and the hub the second time;
#   - "Goodnight, then. The fire stays lit till morning." whole from tick 857,
#     then the prompt again;
#   - nothing under "missing or mismatched keys".
#
# The Down presses wait for the hub's question to finish typing. Before that
# the box shows only the ▼ marker, and a Down has nothing to move to.

idle 20
press controls::KEY_RETURN # begin
idle 130                   # the greeting types itself out
press controls::KEY_RETURN # on to the hub
idle 60                    # its question types out, and the responses appear

press controls::KEY_RETURN # "Have you a room for the night?"
idle 20
press controls::KEY_RETURN # the rest of the answer at once
idle 20
press controls::KEY_RETURN # back to the hub
idle 60

press controls::KEY_DOWN
idle 10
press controls::KEY_RETURN # "Where does the road lead?"
idle 20
press controls::KEY_RETURN # the rest of the first page
idle 20
press controls::KEY_RETURN # the second page
idle 20
press controls::KEY_RETURN # the rest of it
idle 20
press controls::KEY_RETURN # back to the hub
idle 60

2.times do
  press controls::KEY_DOWN
  idle 10
end
press controls::KEY_RETURN # "Any news?"
idle 20
press controls::KEY_RETURN # the rest, and its two responses
idle 20
press controls::KEY_RETURN # "Wolves? Tell me more."
idle 20
press controls::KEY_RETURN
idle 20
press controls::KEY_RETURN # back to the hub
idle 60

2.times do
  press controls::KEY_DOWN
  idle 10
end
press controls::KEY_RETURN # "Any news?" again
idle 20
press controls::KEY_RETURN
idle 20
press controls::KEY_DOWN
idle 10
press controls::KEY_RETURN # "I'd rather not hear it." — straight back
idle 60

3.times do
  press controls::KEY_DOWN
  idle 10
end
press controls::KEY_RETURN # "Nothing, thank you. Goodnight."
idle 20
press controls::KEY_RETURN
idle 20
press controls::KEY_RETURN # the dialogue ends, and the prompt comes back
idle 60

press controls::KEY_RETURN # a second dialogue, from the start
idle 120
