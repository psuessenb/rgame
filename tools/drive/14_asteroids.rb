# Input script for examples/14_asteroids.
#
# Names are the ids the game's action_map binds to (`:left`, `:fire`, ...), not
# the actions it declares — the script stands where the input backend does, so
# it speaks the backend's vocabulary.
#
# The route: title screen -> confirm -> play, then fly and shoot for a while.
# Enough to prove the scene transition fires, the ship responds, and bullets and
# sounds actually leave the scene.

idle 10                   # let the title screen settle
press :confirm            # -> PlayScene (StartScene#on_control reads pressed?)

idle 5
hold :up,   30            # thrust
hold :left, 20            # turn
hold %i[up fire], 40      # thrust and shoot together
hold :fire, 20
hold :right, 25
idle 30                   # drift, so rocks and bullets keep moving on their own
