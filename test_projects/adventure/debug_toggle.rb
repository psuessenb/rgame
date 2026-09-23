# frozen_string_literal: true

# The shell's switch for the debug shapes, on an action of the project's own.
#
# `RGame::Game` already binds F3 to the same channel, and that is the key a
# person playing this reaches for. This exists because the key cannot be
# *driven*: F1, F2 and F3 come from the window's own events, and the scripted
# input backend a driven run uses answers polled actions and never reaches
# `Game#button_down`. An action in the map can be scripted, so the shapes can be
# switched on half-way through a run and the report can show them arriving.
#
# It binds F4 rather than F3 for the same reason the engine leaves Escape
# alone: two things toggling one channel on one key cancel out, and the run
# looks as though nothing is bound at all.
class DebugToggle < RGame::Engine::Component
  ACTION = :debug

  def _attach = @debug = node.system!(RGame::Engine::Debug)

  def _control(actions)
    @debug.toggle(:shapes) if actions.pressed?(ACTION)
  end
end
