# Localization

**Text a game draws is a translation key, and the words live in YAML tables.**
`RGame::Game` loads the tables and picks the player's language at startup. A
node draws an [`Engine::Text`](toolbox.md#text--the-string-a-node-draws) built
from a key. A UI button's `label:` [is a key too](ui.md#labels-are-translation-keys).
`RGame::Engine::I18n` (`rgame/engine/i18n`) holds the tables and the current
language, and every `Text` reads through it.

`examples/localization` shows all of it on one screen: plurals, a variable, a
fallback, a language menu and a saved choice. See [Examples](examples.md#localization).

## Where the tables go

**A game on `RGame::Game` keeps its tables under `locales/` in its media root**,
one or more `.yml` files in Rails' format. The top-level key is the locale, and
keys nest below it:

```yaml
# media/locales/en.yml
en:
  title_menu:
    play: Play
  hud:
    score: "Score: %{score}"
    apples:
      zero: No apples
      one: "%{count} apple"
      other: "%{count} apples"
```

```yaml
# media/locales/de.yml
de:
  title_menu:
    play: Spielen
  hud:
    score: "Punkte: %{score}"
    apples:
      one: "%{count} Apfel"
      other: "%{count} Äpfel"
```

`Game.new` lists every `.yml` under `locales:` and loads each through the asset
manager, sorted by path. `locales:` defaults to `'locales'`. It is relative to
`media_root` unless it is absolute. A directory that does not exist loads
nothing, and every key then shows as itself. See
[Game](game.md#translations-and-the-players-language) for the loading order.

A project from `rgame new` keeps its tables in `assets/locales/`, which is its
media root plus the default. See
[The `rgame` command](cli.md#text-comes-from-a-translation-table).

One file may hold several locales, and several files may hold one. A second load
of a locale merges key by key into what is loaded. A key set twice takes the
later value.

## Drawing translated text

A node builds a `Text` once and reads it in `on_draw`. A read with unchanged
variables and an unchanged language returns the same String and allocates
nothing:

```ruby
class Hud < RGame::Engine::Node2D
  def initialize(**)
    super
    @score = RGame::Engine::Text.new('hud.score', :score)
    @apples = RGame::Engine::Text.new('hud.apples', :count)
    @title = RGame::Engine::Text.new('hud.title')
  end

  def on_draw(renderer, _view)
    renderer.text(@score.with(score: @points), 12, 10)
    renderer.text(@apples.with(count: @apples_held), 12, 30)
    renderer.text(@title, 12, 50)
  end
end
```

A `Text` with no variables goes to `text` as it is, because it answers `to_str`.

A switch of `I18n.locale` renders every `Text` again on its next read. Nothing
subscribes to the switch. [`Text`](toolbox.md#text--the-string-a-node-draws)
covers variables, scopes, `Text.literal` for text that never translates, and
`Text.computed`.

`I18n` itself is a global module, so this works headless, in a spec or anywhere
else:

```ruby
require 'rgame'

i18n = RGame::Engine::I18n
i18n.load(<<~YAML, source: 'locales/game.yml')
  en:
    menu:
      title: Main Menu
      greeting: "Hello, %{name}"
    apples:
      zero: No apples
      one: "%{count} apple"
      other: "%{count} apples"
  de:
    menu:
      title: Hauptmenü
    apples:
      one: "%{count} Apfel"
      other: "%{count} Äpfel"
YAML

i18n.locale = 'de_AT'
i18n.chain                                   # => [:"de-AT", :de, :en]
i18n.t('menu.title')                         # => "Hauptmenü" — from the de table
i18n.t('greeting', scope: 'menu', name: 'Ada') # => "Hello, Ada" — de lacks it, en has it
i18n.t('apples', count: 3)                   # => "3 Äpfel"
i18n.missing_keys(:de)                       # => ["menu.greeting"]
i18n.choose(%w[fr-CA de-CH])                 # => :"de-CH" — the de table covers it
```

## Tables

`load(yaml, source:)` parses a String. `source:` names the file in error
messages. `load_hash` does the same for a Hash, with Symbol or String keys.
`I18n` never opens a file: `RGame::Game` reads the files and hands `load` their
text.

`load` uses `YAML.safe_load` with aliases allowed. It raises
`Psych::DisallowedClass` for an object tag and `Psych::SyntaxError` for broken
YAML. YAML reads an unquoted `on`, `off`, `yes`, `no`, `true`, `false` or `~` as
a boolean or `nil`. `load` raises `ArgumentError` for such a key or value, naming
where it is, so quote it. A number value becomes its text, and so does a
whole-number key. Any other key, such as `1.5`, raises `ArgumentError` too.

Each load compiles every value once. A String becomes a template with its
placeholders already found. `%%{` writes a literal `%{`. A key without
placeholders returns the same frozen String on every call.

`available` lists the locales that have a table, in load order.

## Variables and `t`

`%{name}` in a translation prints a variable. A `Text` declares its variables as
names and receives them as keywords to `with`.

`t(key, scope: nil, **vars)` looks `key` up, or `"scope.key"` when `scope:` is
given, and interpolates `vars`. It raises `ArgumentError` when the translation
uses a variable `vars` does not hold. Variables it does not use are ignored.
`t` allocates on every call, so keep it off the per-frame path.

`render(key, names, vars)` is what a `Text` reads through. It resolves `key` like
`t`, with `vars` holding exactly `names`. A translation whose placeholders are
not `names` goes to the [missing policy](#missing-keys), as
[`Text`](toolbox.md#when-it-renders-again) describes.

## Plurals

A key whose nested keys are all CLDR plural categories (`zero`, `one`, `two`,
`few`, `many`, `other`), with text values and `other` among them, is a plural.
Any other nested Hash is a level of keys. `t` needs `count:` for a plural and
raises `ArgumentError` without it. `count` is also available as `%{count}`. A
`Text` for a plural needs `:count` among its names.

`t` picks the form by these rules, in order:

1. An explicit `zero` form wins for a count of 0, in every language. A table
   without one uses its language's rule: German reads `0 Äpfel` from `other`.
2. The plural rule sorts the count into a category. The rule belongs to the
   table that supplied the key, not to the current locale. English text reached
   through a fallback from `:pl` counts like English.
3. A category the table leaves out reads `other`.

`I18n::PluralRules::BUILT_IN` holds whole-number rules for en, de, nl, sv, da,
nb, fi, it, es, pt, fr, ru, uk, pl, cs, ja, zh, ko and ar. A built-in rule puts a
count that is not an Integer in `other`. A language without a rule counts like
English. `plural_rule(language) { |count| ... }` adds or replaces a rule; its
block returns a category Symbol. A rule for a regional locale, such as `'pt-PT'`,
wins over its language's rule for tables of that locale.

## Locales and the fallback chain

`locale=` switches the language, and `default=` sets the last locale every lookup
falls back to. Both start at `:en`. Both normalize what they are given:
`de_AT`, `'de-at'` and `:'de-AT'` all become `:'de-AT'`, and `normalize` is
public. A locale needs no table of its own.

`chain` lists where a lookup looks, in order: the locale, each shorter prefix of
it, then the default. `I18n` rebuilds it on a switch, not on every lookup. A key
the German table lacks therefore shows the English text in German, when English
is the default.

`choose(preferred)` takes the player's locales, most wanted first. It returns the
first whose own chain meets a table, normalized but not shortened. The default
does not count as a match, and with no match `choose` returns the default.

## The player's language

**`Game.new` sets `I18n.locale` to `I18n.choose(RGame::Core.preferred_locales)`**
after loading the tables: the first locale the operating system prefers that a
table covers, or the default. [App](app.md) describes what
`RGame::Core.preferred_locales` returns on each platform.

A language the player picked belongs between `new` and `start`, because `new`
has already chosen from the OS by then. `examples/localization` saves it with
[`Util::SaveFile`](values.md) and restores it this way:

```ruby
game = MyGame.new
saved = save.read[:language]
if saved.is_a?(String) && !saved.empty?
  RGame::Engine::I18n.locale = RGame::Engine::I18n.choose([saved, *RGame::Core.preferred_locales])
end
game.start
```

Passing the saved locale through `choose` ignores a saved language the game has
no table for. A menu that switches language sets `I18n.locale` and writes the
save. `I18n` holds one language for the whole process, so split-screen players
share it.

## Missing keys

A key is missing when no locale in the chain has it. `missing=` decides what
`t` returns then:

| `missing` | `t` on a missing key |
|---|---|
| `:key` (the start) | returns the key, with its scope |
| `:raise` | raises `I18n::MissingKey`, whose `key` and `chain` say where it looked |
| a callable | calls it with the key and the chain, and returns its result |

Any other value raises `ArgumentError`. A game on `RGame::Game` keeps `:key`, so
a missing key shows as itself on screen.

`missing_keys(locale)` lists the keys the default's table has and the locale's
own chain lacks, in the default table's order. It skips a key the locale gets
from a parent, such as `de-AT` from `de`.

## Specs

**Specs raise on a missing key and check every table against the default.** A
project from `rgame new` does both. Its `spec/spec_helper.rb` loads the tables
before every example:

```ruby
LOCALES = Dir[File.expand_path('../assets/locales/**/*.yml', __dir__)]
          .to_h { |path| [path, File.read(path)] }.freeze

RSpec.configure do |config|
  config.before do
    RGame::Engine::I18n.reset
    LOCALES.each { |path, yaml| RGame::Engine::I18n.load(yaml, source: path) }
    RGame::Engine::I18n.missing = :raise
  end
end
```

Its `spec/locales_spec.rb` expects `missing_keys` to be empty for every locale in
`available`. A key added to `en.yml` and not to `de.yml` then fails `rake`.
[The `rgame` command](cli.md#text-comes-from-a-translation-table) describes both
files.

## `generation`

**`generation` is an Integer that moves whenever what a key resolves to may have
changed.** It moves on every load, on a switch to a different locale or default,
on every `plural_rule`, and on `reset`. A switch to the locale already current leaves it alone. Cached
text compares `generation` with the value it last saw, and resolves again only
when it differs.

`reset` forgets every table and added plural rule. It restores `:en` as locale
and default, and `:key` as the missing policy. rgame's own headless suite calls
`reset` and sets `missing = :raise` before every example.

## What this is not

- **Text is not measured in the engine layer.** A button slot has a fixed width,
  so choose one wide enough for the longest translation.
- **One language per process.** Split-screen players cannot read different
  languages.
- **No right-to-left text or shaping.** The shipped font covers Latin, Greek and
  Cyrillic; nothing selects a font per locale.
- **Only text translates.** Images, audio and other assets have no per-locale
  variant.
- **No `default:`, lazy lookup, array values or symbol links** from Rails.
