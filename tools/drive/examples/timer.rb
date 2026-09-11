# Input script for examples/timer.
#
# Sets off the one-shot twice, well apart, and otherwise leaves the scene alone —
# because the subject of this example is what happens when nobody presses
# anything. Run it long: the race needs more than one lap to be worth reading.
#
#   ruby tools/drive_test_project.rb examples/timer/main.rb --ticks 700
#
# What the report should show:
#
#   - **the last `rect` at (397.7, 0, 3, 26)**, and the same number at any longer
#     budget. That is the whole example in one figure. The mark is drawn where the
#     naive bar had got to when the true one finished its lap, and 397.7 of a
#     480-wide track is 58 beats of 70 — the naive runner keeps 83% of the true
#     cadence, which is the 4.2 frames a beat really takes divided by the 5 it
#     gets rounded up to. It lands in the same place every lap, so the error is a
#     rate and not a stumble;
#   - **404.6 on the first lap only**, at a budget that stops after one (around
#     450 ticks). The naive bar starts with its accumulator aligned and loses the
#     first fraction of a beat rather than a whole one. From the second lap it
#     settles;
#   - **six `rect` and five `text` calls per frame** as the floor — the backdrop,
#     two tracks and two fills, the chime square, and the captions. Everything
#     above that floor is the one-shot;
#   - **the one-shot's banner present for about 72 frames after each Space**, and
#     absent otherwise. It is a `repeating: false` timer calling `queue_free` on
#     its own node, so the extra `rect` and `text` stop together and nothing
#     removes the banner from outside;
#   - **three distinct translates while a banner exists and two without it** —
#     the two runners, plus the banner when it is there.
#
# Nothing here needs a seed: there is no RNG, and a fixed timestep makes the race
# reproducible tick for tick.

idle 60
press controls::KEY_SPACE  # one-shot, while the first lap is still running
idle 200
press controls::KEY_SPACE  # and another, a lap later
idle 200
idle 200
