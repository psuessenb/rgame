# frozen_string_literal: true

require 'etc'
require 'open3'
require 'rbconfig'

# Drives every example and test project with its own script under
# `--allocations`, and fails when any run goes over its budget. `rake
# drive:allocations` runs it, and CI runs that on Linux.
#
#   ruby tools/drive_allocations.rb                      # every project
#   ruby tools/drive_allocations.rb examples/dialogue    # the ones named
#
# **This is the check that sees a whole game.** A spec measures one class with
# the data it was given, and a cop reads one method. Neither saw
# `TileMap#frame_tile` allocate for every animated tile in view: no spec's map
# showed a frame other than the last, and nothing marks the method as per-frame.
# A driven run exercises everything wired together, with a real map.
#
# Several runs go at once, each on its own Xvfb display, since a run spends
# most of its time waiting for its next tick. A test project reading the
# gitignored `media/` is skipped in a checkout without it, and the output says
# so: CI has no `media/`, so there it drives the examples and the test
# projects that bring their own assets.
module DriveAllocations
  ROOT = File.expand_path('..', __dir__)
  HARNESS = File.join(__dir__, 'drive_test_project.rb')
  FIRST_DISPLAY = 110
  WORKERS = Etc.nprocessors.clamp(1, 4)

  Run = Struct.new(:project, :status, :summary, :output)

  module_function

  def projects(named)
    all = Dir.glob('{examples,test_projects}/*/main.rb', base: ROOT)
    return all.sort if named.empty?

    named.map { |dir| File.join(dir.delete_suffix('/'), 'main.rb') }
  end

  def run_all(mains)
    queue = Queue.new
    mains.each { queue << it }
    queue.close
    results = Queue.new
    Array.new(WORKERS) do |worker|
      Thread.new do
        while (main = queue.pop)
          results << drive(main, FIRST_DISPLAY + worker)
        end
      end
    end.each(&:join)
    Array.new(results.size) { results.pop }.sort_by(&:project)
  end

  def drive(main, display)
    project = File.dirname(main)
    return Run.new(project, :skipped, 'reads media/, which this checkout does not have', '') if needs_media?(main)

    output, status = Open3.capture2e({ 'RGAME_SPEC_DISPLAY' => ":#{display}" },
                                     RbConfig.ruby, HARNESS, main, '--allocations', chdir: ROOT)
    Run.new(project, status.success? ? :ok : :failed, summary(output), output)
  end

  def needs_media?(main)
    File.read(File.join(ROOT, main)).include?("'../../media'") && !Dir.exist?(File.join(ROOT, 'media'))
  end

  def summary(output)
    rate = output[/([\d.]+) a second \(budget/, 1]
    share = output[/([\d.]+)% \(budget/, 1]
    rate ? "#{rate} objects a second, on #{share}% of ticks" : output.lines.last.to_s.strip
  end

  def report(runs, out)
    runs.each { |run| out.puts "#{run.status.to_s.ljust(8)}#{run.project.ljust(33)}#{run.summary}" }
    runs.select { it.status == :failed }.each do |run|
      out.puts "\n#{run.project}\n#{run.output[/allocations after.*\z/m] || run.output}"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  runs = DriveAllocations.run_all(DriveAllocations.projects(ARGV))
  DriveAllocations.report(runs, $stdout)
  exit 1 if runs.any? { it.status == :failed }
end
