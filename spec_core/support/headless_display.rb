# frozen_string_literal: true

# Gives the RGame::Core spec suite somewhere to open real windows.
#
# Core owns windows and GL contexts, so its specs cannot avoid creating them.
# What they can avoid is needing a human's desktop: on Linux the suite starts
# its own Xvfb and points SDL at it, so `rake spec:core` runs on a headless
# box and never touches the developer's session.
#
# Elsewhere there is nothing to start — macOS and Windows always have a window
# server, and no Xvfb equivalent exists — so the suite uses the native display.
module HeadlessDisplay
  DISPLAY = ENV.fetch('RGAME_SPEC_DISPLAY', ':97')

  class << self
    # :xvfb when we started one, :native when the platform provides its own.
    def start
      return :native unless x11?

      ensure_xvfb_available
      @pid = spawn('Xvfb', DISPLAY, '-screen', '0', '800x600x24',
                   out: File::NULL, err: File::NULL)
      wait_until_ready
      # Registered before rgame/core is loaded, so it runs *after* Core's own
      # at_exit work (handlers run last-registered-first). The GC pass frees any
      # App still holding a window while the X server is still up — without it
      # Xlib prints a fatal-IO complaint as the process winds down.
      at_exit do
        GC.start
        stop
      end

      ENV['DISPLAY'] = DISPLAY
      # Xvfb has no GPU: without a software rasterizer SDL_GL_CreateContext
      # fails outright and every Core spec dies at App.new.
      ENV['LIBGL_ALWAYS_SOFTWARE'] = '1'
      ENV['GALLIUM_DRIVER'] = 'llvmpipe'
      :xvfb
    end

    # Whether synthetic keyboard input is available. XTEST is an X11 extension,
    # so keyboard-driven specs skip themselves on other platforms rather than
    # fail — see CLAUDE.md's "Platform support".
    def can_inject_keys? = x11?

    def x11? = RUBY_PLATFORM.include?('linux')

    def stop
      return unless @pid

      Process.kill('TERM', @pid)
      begin
        Process.wait(@pid)
      rescue StandardError
        nil
      end
      @pid = nil
    end

    private

    def ensure_xvfb_available
      return if system('command -v Xvfb >/dev/null 2>&1')

      abort "Xvfb not found. The RGame::Core specs open real windows and need it.\n  " \
            'Debian/Ubuntu: sudo apt install xvfb'
    end

    def wait_until_ready
      30.times do
        return if system("DISPLAY=#{DISPLAY} xwininfo -root >/dev/null 2>&1")

        sleep 0.15
      end
      raise "Xvfb on #{DISPLAY} never became ready"
    end
  end
end
