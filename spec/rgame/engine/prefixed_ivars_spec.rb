# frozen_string_literal: true

# Every ivar a node or component in RGame::Engine touches starts with `rgame_`,
# so an ivar a game's subclass names is its own. A collision fails silently and
# far from its cause: `@footing` once lost examples/pits its Footing to y-sort.
#
# The classes come from Ruby, not from a list, so an indirect subclass such as
# UI::TextButton is covered without naming Node2D. For each method a class
# defines itself, its instruction sequence names every ivar it reads, writes or
# tests, blocks included. A method made by attr_reader has none, and its ivar
# is its own name.
RSpec.describe 'the ivars of the classes a game subclasses' do # rubocop:disable RSpec/DescribeClass -- the subject is a rule over many classes
  let(:engine) { RGame::Engine }

  # From ObjectSpace rather than `constants`, which leaves out a private
  # constant such as Scene::Rooms::Cover.
  let(:engine_classes) do
    ObjectSpace.each_object(Class).select do |klass|
      klass.name&.start_with?('RGame::Engine::') && (klass <= engine::Node2D || klass <= engine::Component)
    end
  end

  def engine_module?(mod) = !mod.is_a?(Class) && mod.name&.start_with?('RGame::Engine::')

  def methods_of(mod)
    %i[public_instance_methods private_instance_methods protected_instance_methods]
      .flat_map { mod.public_send(it, false) }
      .map { mod.instance_method(it) }
  end

  def ivars_of(method)
    iseq = RubyVM::InstructionSequence.of(method)
    return [:"@#{method.original_name.to_s.chomp('=')}"] unless iseq

    ivars_in(iseq.to_a).uniq
  end

  def ivars_in(instructions, found = [])
    instructions.each do |item|
      case item
      when Array then ivars_in(item, found)
      when Symbol then found << item if item.start_with?('@')
      end
    end
    found
  end

  # "Class#method (file:line) touches @ivar", one for each unprefixed ivar.
  def unprefixed(owners)
    owners.flat_map do |owner|
      [owner, owner.singleton_class].flat_map { methods_of(it) }.flat_map do |method|
        file, line = method.source_location
        ivars_of(method).reject { it.start_with?('@rgame_') }
                        .map { "#{owner}##{method.name} (#{file}:#{line}) touches #{it}" }
      end
    end
  end

  it 'finds the classes a game subclasses, directly and further down' do
    expect(engine_classes.map(&:name))
      .to include('RGame::Engine::Node2D', 'RGame::Engine::Component', 'RGame::Engine::UI::TextButton',
                  'RGame::Engine::Scene::Rooms::Cover')
  end

  it 'prefixes every ivar the methods of a node or component touch' do
    expect(unprefixed(engine_classes)).to be_empty
  end

  # Collider, WorldBounds and Culling reach a component through `include`, and
  # the Signal DSL, SealedPrivates and Hooks run on the class itself.
  it 'prefixes every ivar the engine modules mixed into them touch' do
    modules = engine_classes.flat_map { it.ancestors + it.singleton_class.ancestors }.uniq.select { engine_module?(it) }
    expect(modules).to include(engine::Components::Collider, engine::Signal::DSL)
    expect(unprefixed(modules)).to be_empty
  end

  describe 'on a class defined here' do
    it 'names the method and the ivar' do
      node = Class.new(engine::Node2D) { def _update(_dt) = @height_above = 2 }
      expect(unprefixed([node])).to contain_exactly(/#_update \(.+_spec\.rb:\d+\) touches @height_above\z/)
    end

    it 'sees an ivar read in a block, tested with defined? and named by attr_reader' do
      component = Class.new(engine::Component) do
        attr_reader :ready

        def _update(_dt) = [1].each { @count = defined?(@seen) }
      end
      expect(unprefixed([component]).map { it[/@\w+\z/] }).to contain_exactly('@ready', '@count', '@seen')
    end

    it 'sees an ivar in a class-level method' do
      component = Class.new(engine::Component) { def self.share = @shared += 1 }
      expect(unprefixed([component])).to contain_exactly(/touches @shared\z/)
    end

    it 'passes a prefixed ivar and a sealed attribute' do
      node = Class.new(engine::Node2D) do
        sealed_accessor :lift

        def _update(_dt) = @rgame_count = 1
      end
      expect(unprefixed([node])).to be_empty
    end
  end
end
