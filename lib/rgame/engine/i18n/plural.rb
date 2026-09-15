# frozen_string_literal: true

module RGame
  module Engine
    module I18n
      # A translation that varies with `count`: one `Template` per CLDR category
      # the table spells out, and the locale of the table it came from, whose
      # language decides which category a count falls into.
      #
      # Internal to `I18n`. A nested Hash in a table compiles to a Plural when
      # every key is a category, every value is text, and `other` is among them;
      # any other Hash is a level of nesting.
      class Plural
        CATEGORIES = %i[zero one two few many other].freeze
        CATEGORY_NAMES = CATEGORIES.map(&:name).freeze

        attr_reader :locale

        def self.forms?(entries)
          entries.key?('other') &&
            entries.all? { |name, value| CATEGORY_NAMES.include?(name) && value.is_a?(String) }
        end

        def initialize(locale, entries)
          @locale = locale
          @forms = entries.to_h { |name, source| [name.to_sym, Template.compile(source)] }.freeze
        end

        # The template for `count`, whose category under this table's language
        # is `category`. An explicit `zero` form wins for 0 in every language,
        # and a category the table leaves out reads `other`.
        def template_for(count, category)
          (count == 0 && @forms[:zero]) || @forms[category] || @forms.fetch(:other) # rubocop:disable Style/NumericPredicate -- count may be any object
        end
      end
    end
  end
end
