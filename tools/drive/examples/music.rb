# Input script for examples/music.
#
# Fades the track in, asks for it again while it plays, pauses and resumes it,
# turns the music down three tenths and the effects down two and up one, fades
# it out and brings it back halfway, fades it out again with a pause in the
# middle, and fades it in from the top.
#
# What the report should show over 600 ticks, in the audio section:
#
#   - **4 × music music.ogg**, one per Enter. The second, while it plays, sends
#     that call and no volume, so it neither restarts nor fades;
#   - **275 × music volume music.ogg**. A fade in is a 0 before the play and
#     sixty steps, one a tick, on ticks 11 to 70 and 475 to 534. The first fade
#     out is 32 steps, from 0.983 to 0.467, and the Enter after it raises the
#     song from 0.476 without a second play reaching the song. The second fade
#     out steps nothing between the pause at 361 and the resume at 393, reaches
#     0 at 430, and puts the song back at 1.0 as it stops;
#   - **1 × music stop music.ogg**, the second fade out arriving. The first was
#     brought back, so it stopped nothing;
#   - **2 × music pause and 2 × music resume**;
#   - **3 × category volume music, 3 × category volume effects and 3 × sound
#     blip.ogg**: a blip for each effects press, none for the music.
#
# In `--texts`, the volume line reads "Music 70%   Effects 90%" from tick 187,
# and the state line reads "paused" twice, 32 ticks each.
#
# **What this run cannot check is how a fade sounds.** Sixty steps a second is a
# number; whether a listener hears them as steps is for a person running the
# example. `test/test_audio.c` measures what one step puts out.
#
# Under `--allocations` it allocates 11.2 objects a second once warm. None of it
# is per frame: the volume line renders again for each of its six changes, the
# blip loads on its first press, and each new call fills its call cache once.

idle 10
press controls::KEY_RETURN # fade in over a second
idle 80
press controls::KEY_RETURN # already playing: asked for, not restarted, no fade
idle 20
press controls::KEY_P # pause
idle 30
press controls::KEY_P # resume
idle 20
3.times do
  press controls::KEY_DOWN # music down a tenth
  idle 4
end
2.times do
  press controls::KEY_LEFT # effects down a tenth, and a blip
  idle 4
end
press controls::KEY_RIGHT # effects up a tenth, and a blip
idle 24
press controls::KEY_ESCAPE # fade out
idle 30
press controls::KEY_RETURN # halfway down: back up from there, not restarted
idle 80
press controls::KEY_ESCAPE # fade out
idle 20
press controls::KEY_P # pause, holding the fade out
idle 30
press controls::KEY_P # resume, and the fade out carries on
idle 80
press controls::KEY_RETURN # stopped by now: fade in from the top
idle 70
