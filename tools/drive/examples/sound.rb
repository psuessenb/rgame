# Input script for examples/sound.
#
# Six presses, spaced out, then two in quick succession so the last pair
# overlaps — a Sample gets a fresh voice per play, which is the thing this
# example is about and the thing the report can actually show.
#
# What the report should show:
#
#   - **eight `sound blip.ogg` lines in the audio section**, one per press. That is
#     the count to assert on: it goes through AudioBus, the AudioDirector and
#     Core::Audio, so a break anywhere in that chain drops it to zero;
#   - one `circle` and **two** `text` calls per frame — the instructions, and the
#     play count through an `Engine::CachedLabel`. The second one's first
#     argument is the cached string, so the report shows it advancing `plays: 0`
#     → `plays: 8` across the run while the call count stays flat;
#   - no clips and no translates — everything here is screen space.
#
# `press` is two ticks, because an edge query compares against the previous
# poll: a key that goes down and never comes up reads as held forever, which is
# a different thing from a press.

idle 10
press controls::KEY_SPACE
idle 20
press controls::KEY_SPACE
idle 20
press controls::KEY_SPACE
idle 20
press controls::KEY_SPACE
idle 20
press controls::KEY_SPACE
idle 20
press controls::KEY_SPACE

idle 6
press controls::KEY_SPACE # these two land close enough together that the first
idle 3                    # voice is still sounding when the second starts
press controls::KEY_SPACE
idle 30
