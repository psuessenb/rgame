# frozen_string_literal: true

module RGame
  module Engine
    module I18n
      # One translated string, compiled once at load: the literal runs and the
      # `%{name}` placeholders between them, so rendering is an append per part
      # rather than a parse. `%%{` in the source is a literal `%{`.
      #
      # Internal to `I18n`; a game reaches translations through `I18n.t` or a
      # `Text`, never through a Template.
      class Template
        PLACEHOLDER = /%%\{|%\{([A-Za-z_]\w*)\}/

        # The variable names the source uses, each once, in order of appearance.
        attr_reader :names

        def self.compile(source)
          parts = []
          literal = +''
          position = 0
          while (match = PLACEHOLDER.match(source, position))
            literal << source[position...match.begin(0)]
            if match[1]
              parts << literal.freeze unless literal.empty?
              parts << match[1].to_sym
              literal = +''
            else
              literal << '%{'
            end
            position = match.end(0)
          end
          literal << source[position..]
          parts << literal.freeze unless literal.empty?
          new(parts)
        end

        def initialize(parts)
          @parts = parts.freeze
          @names = parts.grep(Symbol).uniq.freeze
          @constant = @names.empty? ? -parts.join : nil
        end

        # The string with each placeholder replaced by `vars[name].to_s`. A
        # template without placeholders returns the same frozen String every
        # time. Every name in `names` must be a key of `vars`.
        def render(vars)
          return @constant if @constant

          @parts.each_with_object(+'') do |part, out|
            out << (part.is_a?(Symbol) ? vars.fetch(part).to_s : part)
          end
        end
      end
    end
  end
end
