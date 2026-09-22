# Input script for examples/intro.
#
# Presses Enter once, two seconds in, while the first page is still typing,
# then leaves the timer to turn the rest. Run it with --texts, once in each
# language; the draw-call section alone cannot show which lines were on screen
# when:
#
#   LANG=en_US.UTF-8 ruby tools/drive_test_project.rb examples/intro/main.rb --ticks 1200 --texts
#   LANG=de_DE.UTF-8 ruby tools/drive_test_project.rb examples/intro/main.rb --ticks 1200 --texts
#
# What the report should show under "texts drawn", read off both runs:
#
#   - **each page typing itself out.** Prefixes of a line grow one character at
#     a time, "L" from tick 2, and "Long ago, before the roads had names, a"
#     whole from tick 59. Nothing of the story is drawn whole at tick 0;
#   - **English: 8 lines of the story on 3 pages**, and **German: 10 lines on
#     4 pages**, the last German one "in der die Flamme erlosch." alone. The
#     German story is longer and takes a page more at the same width;
#   - **the rest of page 1 whole at tick 121**, one tick after Enter: Enter
#     reveals a page still typing rather than turning it;
#   - **each later page starting one second plus 20 ms a character after the
#     one before was fully shown**, the timer held back while a page types. A
#     full page holds for about 210 ticks: English page 2 from tick 335 and
#     page 3 from about 735; German page 2 from about 332, page 3 from about
#     705 and page 4 from 1092;
#   - **the hint drawn until the last page and not after it**: 735 frames of
#     "Enter turns the page" in English, 1092 of "Enter blättert um" in German;
#   - one `rect` per frame, the black backdrop at (0, 0, 640, 480);
#   - nothing under "missing or mismatched keys".

idle 120
press controls::KEY_RETURN # shows the rest of the first page at once
idle 1080
