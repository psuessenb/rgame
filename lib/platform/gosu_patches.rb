# frozen_string_literal: true

# Stop Gosu's per-frame callback wrappers from allocating.
#
# gosu-1.4.6/lib/gosu/swig_patches.rb defines every Window callback wrapper in one loop:
#
#   define_method("protected_#{cb}") { |*args| ... !!send(cb, *args) ... }
#
# The `|*args|` splat allocates a throwaway Array on *every* call, even with no arguments.
# Gosu's C loop invokes `update`, `needs_redraw?`, `needs_cursor?` and `draw` once per
# rendered frame (plus `button_*` per input event), so a steady, idle frame still leaks
# ~4 Arrays — an allocation floor no amount of careful game code can get under, and noise
# in the DebugOverlay's per-frame allocation reading (Δ/f).
#
# Redefining the wrappers with fixed arity removes the splat. Gosu is effectively frozen
# (last release 2023-05), so this won't drift out from under us. Each body mirrors Gosu's
# original exactly: once an exception is pending do nothing, otherwise run the callback
# and coerce the result to a boolean (needed by needs_redraw?/needs_cursor?); on error,
# capture it to re-raise on the next tick and unwind the message loop via close!.
module Gosu
  class Window
    {
      0 => %i[update draw needs_redraw? needs_cursor? gain_focus lose_focus],
      1 => %i[button_down button_up gamepad_connected gamepad_disconnected drop]
    }.each do |arity, callbacks|
      callbacks.each do |callback|
        if arity.zero?
          define_method(:"protected_#{callback}") do
            defined?(@_exception) ? false : !!send(callback)
          rescue Exception => e # rubocop:disable Lint/RescueException -- mirror Gosu: catch everything, defer
            @_exception = e
            close!
            false
          end
        else
          define_method(:"protected_#{callback}") do |arg|
            defined?(@_exception) ? false : !!send(callback, arg)
          rescue Exception => e # rubocop:disable Lint/RescueException -- mirror Gosu: catch everything, defer
            @_exception = e
            close!
            false
          end
        end
      end
    end
  end
end
