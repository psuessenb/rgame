# Input script for examples/intro.
#
# Presses Enter once, two seconds in, then leaves the timer to turn the rest.
# Run it with --texts, once in each language; the draw-call section alone cannot
# show which lines were on screen when:
#
#   LANG=en_US.UTF-8 ruby tools/drive_test_project.rb examples/intro/main.rb --ticks 1200 --texts
#   LANG=de_DE.UTF-8 ruby tools/drive_test_project.rb examples/intro/main.rb --ticks 1200 --texts
#
# What the report should show under "texts drawn", read off both runs:
#
#   - **English: 8 lines of the story on 3 pages.** Three lines from tick 0,
#     three from tick 121, and the last two from tick 481. Nothing in en.yml
#     breaks the story; it is one line there;
#   - **German: 10 lines on 4 pages.** The same first three turns, then the last
#     line, "in der die Flamme erlosch.", alone from tick 842. The German story
#     is longer and takes a page more at the same width;
#   - **page 2 at tick 121**, one tick after Enter, not six seconds in: Enter
#     turned it;
#   - **each later page 360 or 361 ticks after the one before**, the six-second
#     timer. Enter re-arms it before that tick's update and the timer re-arms
#     itself after one, which is the tick between the two;
#   - **the hint drawn until the last page and not after it**: 481 frames of
#     "Enter turns the page" in English, 842 of "Enter blättert um" in German;
#   - one `rect` per frame, the black backdrop at (0, 0, 640, 480);
#   - nothing under "missing or mismatched keys".

idle 120
press controls::KEY_RETURN # turns the first page early; the timer restarts
idle 1080
