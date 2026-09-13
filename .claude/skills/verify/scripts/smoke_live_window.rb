# frozen_string_literal: true

require_relative 'live_window'

BIN = File.join(LiveWindow::PROJECT_ROOT, 'build/rgame')
abort "#{BIN} not built — run `make` first" unless File.executable?(BIN)

asan = `nm -C #{BIN} 2>/dev/null`.include?('__asan')
puts "binary: #{BIN} (#{asan ? 'sanitizer build' : 'plain build'})"

failures = []

LiveWindow.run(cmd: [BIN], title: 'rgame', display: ':99', asan: asan) do |w|
  puts "window: 0x#{w.window_id.to_s(16)}  focus: 0x#{w.keys.focused_window.to_s(16)}"
  sleep 0.7

  w.keys.tap('Escape')
  status = w.wait_for_exit(timeout: 10)

  failures << 'engine did not exit after synthetic Escape' if status.nil?
  if status && !status.success?
    failures << "engine exited with status #{status.exitstatus} " \
                '(42 = sanitizer finding; see log)'
  end
  failures << "sanitizer report:\n#{w.sanitizer_report}" if asan && !w.sanitizer_clean?

  puts w.log.empty? ? '(no app output)' : "--- app output ---\n#{w.log}"
end

if failures.empty?
  puts "\nPASS — live window opened, took synthetic input, exited cleanly" \
       "#{', no sanitizer findings' if asan}"
  exit 0
end

puts "\nFAIL"
failures.each { |f| puts "  - #{f}" }
exit 1
