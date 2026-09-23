# frozen_string_literal: true

require 'rubocop-ast'

# A memoized helper in an example group is `let` written by hand.
#
#     def resolver = @resolver ||= CollisionSystem.new(...)   # this
#     let(:resolver) { CollisionSystem.new(...) }             # means this
#
# Both memoize for the length of one example, so the difference is only that the
# first hides the instance variable inside a `def` — which is exactly why no cop
# catches it. `RSpec/InstanceVariable` searches for `(ivar :@x)` nodes, and
# `@x ||= y` parses to `(or-asgn (ivasgn :@x) y)`, containing no `ivar` node at
# all. The rule would otherwise be one more line in a skill that someone has to
# remember, so it is checked here instead — see "Design out misuse" in CLAUDE.md.
#
# **What is scanned is derived, not listed**: every `.rb` file under both suite
# roots, so a new spec is covered the day it is written.
#
# What this deliberately allows is the same shape inside a class body, where it
# is not a `let` substitute but ordinary production-shaped code: a node or
# component defined with `Class.new` to be driven by the code under test cannot
# reach a `let`, and its own memoized readers are the engine's idiom, not the
# spec's. `RSpec::Matchers.define` is allowed for the same reason.
RSpec.describe 'spec style' do # rubocop:disable RSpec/DescribeClass -- the subject is the two suite trees, not a class
  # A scope that is not an example group: a helper defined here belongs to the
  # object being defined, and has no `let` available to it.
  def class_scope?(node)
    return true if %i[class module sclass].include?(node.type)
    return false unless node.block_type?

    send_node = node.send_node
    send_node.method?(:new) && %w[Class Struct].include?(send_node.receiver&.source) ||
      send_node.method?(:define) && %w[Data RSpec::Matchers].include?(send_node.receiver&.source)
  end

  # The `def` an ivar memoization sits in, or nil when a class body encloses it
  # first. Walking outwards and stopping at whichever comes first is what keeps a
  # `def` inside a `Class.new` inside a `def` attributed to the class.
  def enclosing_helper(node)
    node.each_ancestor.each do |ancestor|
      return nil if class_scope?(ancestor)
      return ancestor if %i[def defs].include?(ancestor.type)
    end
    nil
  end

  def memoized_helpers(path)
    source = RuboCop::AST::ProcessedSource.new(File.read(path), RUBY_VERSION.to_f)
    return [] if source.ast.nil?

    source.ast.each_node(:or_asgn).filter_map do |assignment|
      next unless assignment.children.first.ivasgn_type?

      helper = enclosing_helper(assignment)
      next if helper.nil?
      next if helper.each_ancestor.any? { |ancestor| class_scope?(ancestor) }

      "#{path}:#{helper.loc.line} — #{helper.method_name}"
    end
  end

  # The one place the rule loses. `a_mover`'s wall-only groups never read this
  # collider, and a sixth `let` would put them over RuboCop's memoized-helper
  # limit — so it stays a method, and the trade is recorded rather than silent.
  let(:exempt) { ['spec/support/shared_examples/a_mover.rb:45 — floor'] }

  let(:suite_files) do
    root = File.expand_path('..', __dir__)
    %w[spec spec_core].flat_map { |dir| Dir[File.join(root, dir, '**', '*.rb')] }
                      .map { |path| path.delete_prefix("#{root}/") }
  end

  it 'has no helper that memoizes into an instance variable, which is a let' do
    expect(suite_files.flat_map { |path| memoized_helpers(path) } - exempt).to eq([])
  end
end
