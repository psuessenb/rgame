# Input script for examples/localization.
#
# Counts the apples down to none in English, picks Deutsch and counts in German,
# goes back to the system language, and ends by picking Deutsch again, which
# saves it. Run it with --texts; the draw-call section alone cannot show a
# switch:
#
#   ruby tools/drive_test_project.rb examples/localization/main.rb --ticks 140 --texts
#
# What the report should show under "texts drawn", read off a run with
# LANG=en_US.UTF-8 and no save:
#
#   - **English from tick 0**: "Localization", "3 apples", "Current locale: en-US",
#     "Language", "Use the system language". The locale is whatever the OS
#     prefers; under LANG=C it is "en", the default;
#   - "2 apples", "1 apple" and **"No apples"**, English's own `zero:`;
#   - **German from tick 42**: "Lokalisierung", "0 Äpfel",
#     "Aktuelles Gebietsschema: de", "Sprache", "Systemsprache verwenden", then
#     "1 Apfel". German has no `zero:`, so zero reads "0 Äpfel";
#   - **"Left and right change the count" on every one of the 140 frames**. German
#     lacks `hud.hint`, so it falls back to English;
#   - "English" and "Deutsch" on every frame too: they are literals;
#   - more frames of "Localization" than the 42 before German, because the
#     system-language step shows English again before Deutsch is picked a second
#     time;
#   - no string that is a key: nothing starting with `hud.`, `language.` or
#     `title`.
#
# It leaves `language.json` holding "de" in the save directory, which the
# harness removes after the run. To see the save read back, set
# `RGAME_SAVE_DIR` for this run and for tools/drive/examples/localization_saved.rb
# after it.

idle 10

press controls::KEY_LEFT    # 3 -> 2 apples
idle 4
press controls::KEY_LEFT    # 1 apple
idle 4
press controls::KEY_LEFT    # No apples
idle 10

press controls::KEY_DOWN    # English -> Deutsch
idle 4
press controls::KEY_RETURN  # German
idle 10

press controls::KEY_RIGHT   # 1 Apfel
idle 4
press controls::KEY_LEFT    # 0 Äpfel
idle 10

press controls::KEY_DOWN    # Deutsch -> system
idle 4
press controls::KEY_RETURN  # the OS's language, and the save forgotten
idle 10

press controls::KEY_UP      # system -> Deutsch
idle 4
press controls::KEY_RETURN  # German again, and saved
idle 20
