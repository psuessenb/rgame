# frozen_string_literal: true

# Synthetic keyboard input to a live X11 window, via the XTEST extension.
#
# Uses Ruby's stdlib `fiddle` to dlopen libX11/libXtst directly: no gems, no
# dev headers, no root, nothing to install. Verified working against both a
# Gosu window and rgame's own SDL window under Xvfb.
#
# Why XTEST and not XSendEvent: XSendEvent-delivered events carry
# send_event=True, and SDL ignores those by design. XTEST injects at the X
# server's input layer, so the event is indistinguishable from a real
# keypress. (This is also why `xdotool key --window <id>`, which uses
# XSendEvent, is the wrong tool for SDL apps — plain `xdotool key` would work,
# but we don't need xdotool at all.)
#
#   x = XKeys.new(':99')
#   x.tap('Left')
#   x.hold('space') { sleep 0.3 }
#
# Key names are X keysym names: Left/Right/Up/Down, Return, space, Escape,
# a..z, F1. `xev` or /usr/include/X11/keysymdef.h are the reference.

require 'fiddle'

class XKeys
  REVERT_TO_PARENT = 1
  CURRENT_TIME = 0

  def initialize(display_name)
    x11 = Fiddle.dlopen('libX11.so.6')
    xtst = Fiddle.dlopen('libXtst.so.6')

    @open       = fn(x11, 'XOpenDisplay',     [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    @flush      = fn(x11, 'XFlush',           [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @sync       = fn(x11, 'XSync',            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
    @str2keysym = fn(x11, 'XStringToKeysym',  [Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG)
    @keysym2kc  = fn(x11, 'XKeysymToKeycode', [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG], Fiddle::TYPE_CHAR)
    @setfocus   = fn(x11, 'XSetInputFocus',
                     [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_LONG],
                     Fiddle::TYPE_INT)
    @getfocus   = fn(x11, 'XGetInputFocus',
                     [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @warp       = fn(x11, 'XWarpPointer',
                     [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG,
                      Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT,
                      Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT],
                     Fiddle::TYPE_INT)
    @fakekey    = fn(xtst, 'XTestFakeKeyEvent',
                     [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_LONG],
                     Fiddle::TYPE_INT)

    @display_name = display_name
    @display = @open.call(display_name)
    raise "cannot open display #{display_name}" if @display.null?
  end

  # Find a window id by (substring of) its title, waiting for it to appear.
  # Shells out to xwininfo rather than walking the window tree through more
  # Fiddle — that is a lot of struct marshalling for something x11-utils
  # already prints.
  def find_window(title, timeout: 15.0)
    deadline = now + timeout
    loop do
      tree = `DISPLAY=#{@display_name} xwininfo -root -tree 2>/dev/null`
      line = tree.lines.find { |l| l.match?(/"[^"]*#{Regexp.escape(title)}[^"]*"/) }
      return Integer(line[/0x[0-9a-f]+/], 16) if line

      raise "window matching #{title.inspect} never appeared on #{@display_name}" if now > deadline

      sleep 0.1
    end
  end

  # Which window currently owns keyboard focus (1 == PointerRoot).
  def focused_window
    win = Fiddle::Pointer.malloc(8)
    rev = Fiddle::Pointer.malloc(8)
    @getfocus.call(@display, win, rev)
    win[0, 8].unpack1('Q')
  end

  # Defensive, not usually necessary: SDL takes input focus for its own window
  # when it maps it, and under a bare Xvfb there is no window manager to argue.
  # Call it anyway when several windows exist or a WM is running.
  def focus(window_id)
    @setfocus.call(@display, window_id, REVERT_TO_PARENT, CURRENT_TIME)
    @sync.call(@display, 0)
  end

  def warp_pointer(x, y)
    @warp.call(@display, 0, 0, 0, 0, 0, 0, x, y)
    @sync.call(@display, 0)
  end

  def keycode(name)
    keysym = @str2keysym.call(name)
    raise "unknown keysym #{name.inspect}" if keysym.zero?

    kc = @keysym2kc.call(@display, keysym) & 0xFF
    raise "no keycode for #{name.inspect} on this layout" if kc.zero?

    kc
  end

  def press(name)   = fake(name, 1)
  def release(name) = fake(name, 0)

  # A discrete press+release. `settle` must exceed one frame (16ms at 60fps) or
  # the app's event pump can miss the pair entirely.
  def tap(name, settle: 0.05)
    press(name)
    sleep settle
    release(name)
    sleep settle
  end

  # Hold a key across the block — exercises the "is this key held" polling path,
  # which is a different code path from discrete button events and can break
  # independently of it.
  def hold(name)
    press(name)
    yield
  ensure
    release(name)
  end

  private

  def fake(name, is_press)
    @fakekey.call(@display, keycode(name), is_press, CURRENT_TIME)
    @flush.call(@display)
  end

  def fn(lib, name, args, ret) = Fiddle::Function.new(lib[name], args, ret)
  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
