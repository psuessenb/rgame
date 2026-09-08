# Input script for examples/music.
#
# Starts the track, tries to start it twice more while it is already going,
# stops it, and starts it again.
#
# What the report should show, in the audio section:
#
#   - **4 x music music.ogg and 1 x music stop**. Every start is emitted, because the
#     scene deliberately keeps no copy of "is it playing" — so this count is
#     presses, not restarts;
#   - two `rect` and two `text` calls per frame.
#
# **What this run cannot check is the interesting half.** The report proves the
# events were emitted and reached the device. Whether `Audio#play_music`'s guard
# actually stopped presses two and three from restarting the track, and whether
# the loop wraps without a click at 16.6s, are both facts about what came out of
# a speaker — only a person listening can confirm either.

idle 10
press controls::KEY_RETURN # start
idle 40
press controls::KEY_RETURN # already playing: emitted, but must not restart
idle 40
press controls::KEY_RETURN # again
idle 40
press controls::KEY_ESCAPE # stop
idle 20
press controls::KEY_RETURN # start over from zero
idle 40
