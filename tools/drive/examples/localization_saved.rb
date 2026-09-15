# Input script for examples/localization, run after localization.rb against the
# same RGAME_SAVE_DIR:
#
#   RGAME_SAVE_DIR=/tmp/localization ruby tools/drive_test_project.rb \
#     examples/localization/main.rb --script tools/drive/examples/localization_saved.rb \
#     --ticks 30 --texts
#
# It presses nothing. What the report should show under "texts drawn": **German
# from tick 0** ("Lokalisierung", "3 Äpfel", "Aktuelles Gebietsschema: de"),
# whatever the OS prefers. The example read the saved language between `Game.new` and `start`,
# so no English frame is drawn first.

idle 30
