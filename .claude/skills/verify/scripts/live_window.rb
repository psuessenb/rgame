# frozen_string_literal: true

# Harness for the live-window tier: boot a private Xvfb, launch a windowed app
# on it with software GL, hand you an XKeys injector, tear everything down.
#
#   require_relative 'live_window'
#
#   LiveWindow.run(cmd: ['build/rgame'], title: 'rgame', asan: true) do |w|
#     w.keys.tap('Escape')
#     w.wait_for_exit
#   end
#
# Everything here is verified working on this machine (Ubuntu, Wayland session
# — Xvfb sidesteps Wayland entirely, which is why this works at all).

require_relative 'xkeys'
require 'tmpdir'

class LiveWindow
  PROJECT_ROOT = File.expand_path('../../../..', __dir__)

  attr_reader :keys, :log_path, :pid

  # display: pick a number no other test is using; parallel runs must differ.
  # asan:    set ASAN_OPTIONS so a leak fails the run loudly (see SKILL.md).
  def self.run(cmd:, title:, display: ':99', asan: false, env: {}, timeout: 20.0)
    w = new(cmd: cmd, title: title, display: display, asan: asan, env: env, timeout: timeout)
    w.start
    yield w
  ensure
    w&.stop
  end

  def initialize(cmd:, title:, display:, asan:, env:, timeout:)
    @cmd = cmd
    @title = title
    @display = display
    @asan = asan
    @env = env
    @timeout = timeout
    @log_path = File.join(Dir.tmpdir, "live_window_#{Process.pid}_#{rand(1 << 16)}.log")
  end

  def start
    @xvfb = spawn('Xvfb', @display, '-screen', '0', '800x600x24',
                  out: File::NULL, err: File::NULL)
    wait_for_xserver

    @pid = spawn(child_env, *@cmd, chdir: PROJECT_ROOT,
                                   out: @log_path, err: [@log_path, 'a'])
    @keys = XKeys.new(@display)
    @window = @keys.find_window(@title)
    # Give the app a few frames after mapping before sending anything.
    sleep 0.3
    self
  end

  def window_id = @window
  def log = File.exist?(@log_path) ? File.read(@log_path) : ''

  # Wait for the app to exit on its own (e.g. after a synthetic Escape).
  # Returns the exit status, or nil if it had to be killed.
  def wait_for_exit(timeout: @timeout)
    deadline = now + timeout
    loop do
      pid, status = Process.waitpid2(@pid, Process::WNOHANG)
      if pid
        @reaped = true
        return status
      end
      return nil if now > deadline

      sleep 0.1
    end
  end

  # True if ASan reported anything (leak, overflow, UB) in the app's output.
  def sanitizer_clean? = !log.match?(/ERROR: (AddressSanitizer|LeakSanitizer)|runtime error:/)

  def sanitizer_report = log[/(ERROR: (AddressSanitizer|LeakSanitizer)|runtime error:).*/m]

  def stop
    unless @reaped
      Process.kill('KILL', @pid) if @pid
      begin
        Process.wait(@pid)
      rescue StandardError
        nil
      end
    end
    return unless @xvfb

    Process.kill('TERM', @xvfb)
    begin
      Process.wait(@xvfb)
    rescue StandardError
      nil
    end
  end

  private

  def child_env
    base = {
      'DISPLAY' => @display,
      # Force Mesa's software rasterizer: Xvfb has no GPU, and without these
      # SDL_GL_CreateContext fails outright.
      'LIBGL_ALWAYS_SOFTWARE' => '1',
      'GALLIUM_DRIVER' => 'llvmpipe',
      # Absolute, so `bundle exec` works regardless of the driver's cwd.
      # Without it you get a bare "Could not locate Gemfile" and the window
      # simply never appears — which looks exactly like a broken injector.
      'BUNDLE_GEMFILE' => File.join(PROJECT_ROOT, 'Gemfile')
    }
    base['ASAN_OPTIONS'] = 'detect_leaks=1:exitcode=42:abort_on_error=0' if @asan
    base.merge(@env)
  end

  def wait_for_xserver
    30.times do
      return if system("DISPLAY=#{@display} xwininfo -root >/dev/null 2>&1")

      sleep 0.15
    end
    raise "Xvfb on #{@display} never became ready"
  end

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
