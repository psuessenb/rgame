# Input script for examples/14_asteroids.
#
# Names are physical ids from RGame::Util::Controls, because the script stands
# where RGame::Core::Input does and that is what the input backend now speaks.
#
# The route: title screen -> ui_confirm -> play, then fly and shoot for a while.
# Enough to prove the scene transition fires, the ship responds, and bullets and
# sounds actually leave the scene.

idle 10                          # let the title screen settle
press controls::KEY_RETURN       # -> PlayScene (StartScene reads pressed?(:ui_confirm))

idle 5
hold controls::KEY_UP, 30        # thrust
hold controls::KEY_LEFT, 20      # turn
hold [controls::KEY_UP, controls::KEY_SPACE], 40 # thrust and shoot together
hold controls::KEY_SPACE, 20
hold controls::KEY_RIGHT, 25
idle 30 # drift, so rocks and bullets keep moving
