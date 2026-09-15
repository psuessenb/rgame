# frozen_string_literal: true

require_relative 'i18n'

module RGame
  module Engine
    # The string a node draws: a translation key, resolved through `I18n` and
    # kept until one of its inputs changes — a variable, or the language.
    #
    #   @score = Engine::Text.new('hud.score', :score)       # built once, e.g. in initialize
    #   renderer.text(@score.with(score: @points), 12, 10)   # every frame: cached, no allocation
    #
    # The names a `Text` is built with become the keywords of its `with`, so a
    # forgotten or misspelt variable is Ruby's own `ArgumentError`. `to_s` reads
    # a `Text` with the values its last `with` was given — so whatever draws it,
    # a button's label among them, needs no values of its own — and raises
    # before the first `with`. A `Text` with no names is read with `to_s`
    # alone. Reading one whose variables and
    # `I18n.generation` are unchanged returns the same frozen String and
    # allocates nothing; otherwise it renders again. A `Text` never subscribes to
    # `I18n`: it compares one Integer, so it holds nothing that could keep it
    # alive.
    #
    # `Text.literal` is a string that is never translated, and `Text.computed` a
    # string a block builds. Both answer `with` and `to_s` the same way, so
    # whatever draws a `Text` never asks which kind it holds.
    class Text
      NAME = /\A[a-z_][A-Za-z0-9_]*\z/
      private_constant :NAME

      class << self
        # A `Text` that shows `string` in every language.
        def literal(string) = Literal.new(string)

        # A `Text` whose string the block builds from the keywords `names`, for
        # text that is formatted rather than looked up. The block runs when a
        # keyword or `I18n.generation` changes, never on an unchanged read, so a
        # block that calls `I18n.t` follows the language too:
        #
        #   @clock = Engine::Text.computed(:seconds) { |seconds:| format_clock(seconds) }
        def computed(*names, &block) = Computed.new(names, block)
      end

      # Generates the module that gives a `Text` its `with` for one list of
      # names, the first time that list is seen, and shares it after.
      module Accessors
        @cache = {}

        def self.for(names)
          @cache[names] ||= generate(names)
        end

        class << self
          private

          def generate(names)
            names.each do |name|
              raise ArgumentError, "#{name.inspect} cannot be a variable name" unless NAME.match?(name)
            end

            Module.new.tap { |mod| mod.module_eval(accessor_source(names), __FILE__, __LINE__) }
          rescue SyntaxError
            raise ArgumentError, "#{names.inspect} cannot all be variable names"
          end

          def accessor_source(names)
            return <<~RUBY if names.empty?
              def with = to_s

              def to_s
                return @string if @generation == ::RGame::Engine::I18n.generation

                refresh({})
              end
            RUBY

            <<~RUBY
              def with(#{names.map { "#{it}:" }.join(', ')})
                if @generation == ::RGame::Engine::I18n.generation && #{names.map { "@_var_#{it} == #{it}" }.join(' && ')}
                  return @string
                end

                #{names.map { "@_var_#{it} = #{it}" }.join('; ')}
                refresh({ #{names.map { "#{it}: #{it}" }.join(', ')} })
              end

              def to_s
                return @string if @generation == ::RGame::Engine::I18n.generation
                unless defined?(@_var_#{names.first})
                  raise ArgumentError, "\#{describe} needs #{names.map { "#{it}:" }.join(', ')}; call with first"
                end

                refresh({ #{names.map { "#{it}: @_var_#{it}" }.join(', ')} })
              end
            RUBY
          end
        end
      end
      private_constant :Accessors

      # The key as given, without its scope.
      attr_reader :key

      # The variable names `with` takes, sorted.
      attr_reader :names

      attr_reader :scope

      # A `Text` for `key`, whose translation prints the variables `names`.
      # `scope: 'title_menu'` with key `'play'` resolves `'title_menu.play'`.
      def initialize(key, *names, scope: nil)
        @key = key.to_s.freeze
        self.scope = scope
        declare(names)
      end

      # Changes the scope the key resolves under; the next read resolves again.
      def scope=(scope)
        @scope = scope&.to_s&.freeze
        @path = (@scope ? "#{@scope}.#{@key}" : @key).freeze
        @generation = nil
      end

      private

      def declare(names)
        @names = names.map(&:to_sym).sort.freeze
        raise ArgumentError, "#{describe} declares a variable twice" if @names.uniq.size != @names.size

        extend(Accessors.for(@names))
      end

      def refresh(vars)
        generation = I18n.generation
        @string = render(vars)
        @generation = generation
        @string
      end

      def render(vars) = I18n.render(@path, @names, vars).freeze

      def describe = "Text #{@path.inspect}"

      # A `Text` that is not translated: the same `with` and `to_s`, answering
      # with one String.
      class Literal < Text
        def initialize(string) # rubocop:disable Lint/MissingSuper -- a literal has no key to resolve
          @string = -string.to_s
          @names = [].freeze
        end

        def with = @string
        def to_s = @string

        # A literal ignores a scope: there is no key to put one in front of.
        def scope=(_scope); end
      end
      private_constant :Literal

      # A `Text` built by a block from its keywords instead of from a key.
      class Computed < Text
        def initialize(names, block) # rubocop:disable Lint/MissingSuper -- a computed text has no key to resolve
          raise ArgumentError, 'Text.computed needs a block' unless block

          @block = block
          declare(names)
        end

        # A computed text ignores a scope: there is no key to put one in front of.
        def scope=(_scope); end

        private

        def render(vars) = @block.call(**vars)

        def describe = 'Text.computed'
      end
      private_constant :Computed
    end
  end
end
