# frozen_string_literal: true

module RGame
  module Engine
    module I18n
      # CLDR plural categories for whole numbers, one rule per language. A rule
      # takes the `count` a caller passed and returns one of `Plural::CATEGORIES`.
      # Every built-in rule answers `:other` for a count that is not an Integer,
      # because fractional counts have categories of their own that no built-in
      # table spells out.
      #
      # Rules are keyed by language, and `I18n.plural_rule` adds or replaces one;
      # a language with no rule counts like English.
      #
      # Source: the CLDR plural rules, https://www.unicode.org/cldr/charts/latest/supplemental/language_plural_rules.html
      module PluralRules
        TWO_TO_FOUR = (2..4)
        TWELVE_TO_FOURTEEN = (12..14)

        def self.whole(&rule) = ->(count) { count.is_a?(Integer) ? rule.call(count.abs) : :other } # rubocop:disable Performance/RedundantBlockCall -- the rule runs after whole has returned, where yield has no block

        def self.slavic_few?(count) = TWO_TO_FOUR.cover?(count % 10) && !TWELVE_TO_FOURTEEN.cover?(count % 100)

        def self.million(count) = count.positive? && (count % 1_000_000).zero? ? :many : :other

        ONE_OTHER = whole { |n| n == 1 ? :one : :other }
        ONE_MILLION_OTHER = whole { |n| n == 1 ? :one : million(n) }
        ZERO_ONE_MILLION_OTHER = whole { |n| n <= 1 ? :one : million(n) }

        EAST_SLAVIC = whole do |n|
          if n % 10 == 1 && n % 100 != 11 then :one
          elsif slavic_few?(n) then :few
          else :many
          end
        end

        POLISH = whole do |n|
          if n == 1 then :one
          elsif slavic_few?(n) then :few
          else :many
          end
        end

        CZECH = whole do |n|
          if n == 1 then :one
          elsif TWO_TO_FOUR.cover?(n) then :few
          else :other
          end
        end

        ARABIC = whole do |n|
          case n
          when 0 then :zero
          when 1 then :one
          when 2 then :two
          else
            case n % 100
            when 3..10 then :few
            when 11..99 then :many
            else :other
            end
          end
        end

        OTHER = ->(_count) { :other }

        BUILT_IN = {
          en: ONE_OTHER, de: ONE_OTHER, nl: ONE_OTHER, sv: ONE_OTHER, da: ONE_OTHER, nb: ONE_OTHER, fi: ONE_OTHER,
          it: ONE_MILLION_OTHER, es: ONE_MILLION_OTHER,
          fr: ZERO_ONE_MILLION_OTHER, pt: ZERO_ONE_MILLION_OTHER,
          ru: EAST_SLAVIC, uk: EAST_SLAVIC, pl: POLISH, cs: CZECH,
          ja: OTHER, zh: OTHER, ko: OTHER,
          ar: ARABIC
        }.freeze

        DEFAULT = ONE_OTHER
      end
    end
  end
end
