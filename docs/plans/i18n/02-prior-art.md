# Prior art, and what was rejected

## How others answer it

### Rails I18n

The format this plan adopts. YAML whose top-level key is the locale, so one file
may hold several; every file under `config/locales` loads; `%{var}`
interpolation; `count:` selects among plural keys; `scope:` prefixes a key.
Plural *rules* beyond one/other come from the `rails-i18n` gem, which carries a
rule per language keyed by CLDR category (`zero one two few many other`).
Missing translations can be configured to raise, which Rails' own generators
turn on for the test environment
(`config.i18n.raise_on_missing_translations`).

What it does not give a game: `I18n.t` is a per-call lookup that allocates, and
views re-render per request, so caching is never its concern.

### Godot

`TranslationServer` is a process-global singleton. Controls translate their
`text` automatically (`auto_translate_mode`, on `Node` in Godot 4): the text *is*
the key, an untranslated key shows itself, and controls re-translate when the
locale changes. Text set from code after `_ready` is not auto-translated, so
dynamic text calls `tr()` by hand
([TranslationServer, Godot 4.4](https://docs.godotengine.org/en/4.4/classes/class_translationserver.html);
[Phrase: Godot localization](https://phrase.com/blog/posts/godot-game-localization/)).

What this plan takes: widgets translating by default, and a global server. What
it does not: key-shows-itself as the *silent* default, because with Rails-style
dotted keys that puts `menu.play` on a player's screen with nothing reporting it.

### Unity Localization

`LocalizedString` is a table reference plus arguments. It raises `StringChanged`
when the locale or an argument changes, and callers subscribe in `OnEnable` and
unsubscribe in `OnDisable`
([Unity Localization: Scripting](https://docs.unity3d.com/Packages/com.unity.localization@1.4/manual/Scripting.html)).

This is the closest shape to `Text`: a retained object holding a key and its
variables. The difference is the change notification. Unity's is a subscription
a caller must remember to remove, which is exactly the remembered rule that
CLAUDE.md's "Design out misuse" rejects, and the AudioBus leak in
`basic-examples.md` shows what a forgotten one costs here. `Text` polls one
Integer instead.

### What none of them gives us

**A per-frame read that allocates nothing.** Each resolves on an event and
hands a String to a retained widget. A game in this engine draws text
immediately every frame, so the retained object has to be the thing drawn from,
and its read has to be free. That is `Text#with`.

### Steam (for decision 5)

SteamPipe splits every file into ~1 MB chunks, compresses and encrypts each, and
on an update uploads only the chunks that differ. For pack files it advises
keeping changes localized, not reshuffling asset order, limiting pack size to
1–2 GB, compressing per asset rather than whole-pack, and avoiding a table of
contents of absolute offsets, which turns one changed 8-byte number into a new
1 MB chunk. For Unreal it recommends padding to 1 MB
([Steamworks: Uploading to Steam](https://partner.steamgames.com/doc/sdk/uploading)).

Loose files therefore patch well, and a pack is optional. When one is wanted,
the constraints fall on whatever writes it. The reader-side requirement is only
that every read goes through a single seam.

### SDL

`SDL_GetPreferredLocales` (since SDL 2.0.14) returns the user's locales in
preference order as `SDL_Locale { language, country }`. The language is ISO-639
and the country ISO-3166 or `NULL`. The array is freed with one `SDL_free`
([SDL2 wiki](https://wiki.libsdl.org/SDL2/SDL_GetPreferredLocales)). It is
available on the CI platforms' SDL builds: Ubuntu's `libsdl2-dev`, Homebrew's
sdl2-compat over SDL3, and MSYS2's SDL2. Step 2 confirms what each runner
returns.

## Considered and rejected

### A second object for translated text beside `CachedLabel`

*Attraction:* no rename, and `CachedLabel` keeps its seven call sites.
*Fails because* it creates two objects answering "which string does this node
draw", with different change rules. The first translated score has to choose
between them, and whichever it picks loses one input. This is issue C7, and it is
the parallel-vocabulary smell CLAUDE.md names.

### Positional variables: `@where[@player_name, @level]`

*Attraction:* zero allocation, and it was the first shape measured.
*Fails because* the syntax is unusual, and the order is a convention the reader
has to remember. Swapped arguments draw wrong text silently. Keywords into a
declared signature cost the same zero objects and fail loudly.

### A `to_str` object passed straight to `renderer.text`

*Attraction:* `renderer.text(@score, x, y)` reads best, and the real renderer's
`StringValue` already accepts `to_str`.
*Fails because* the variables then have to be pushed in `on_update`
(`@score.update(points)`), spreading one label over two methods, with a forgotten
update left silent. The renderer contract and `FakeRenderer#string` would also
have to learn `to_str` (constraint 4). And the conversion is implicit, which
makes a reader stop to find out why an object is accepted as a String.

### Setters in `on_update`, read in `on_draw`

*Attraction:* zero allocation, plain attribute writers.
*Fails because* of the same two-method split and silent forgotten setter.

### A `Text` bound to its node's readers by Symbol

*Attraction:* a widget could hold one and stay live with nothing pushing it.
*Fails because* it names methods by Symbol, needs public readers, and reports a
typo only when read.

### `Engine::Label` as the class name

*Attraction:* reads best in the common case.
*Fails because* a `UI::Label` widget (a line of text a layout places) is likely,
and inside `module UI` a bare `Label` would resolve to it. Every UI file would
then have to spell out the other one, with a missed spelling failing only when
called.

### A system on the root, like `Players`

*Attraction:* specs isolated for free.
*Fails because* nothing outside the tree could translate, including a `Text`
built in `initialize` (fact C15), and language is process state everywhere else.

### A String is a key, a Symbol a literal, or the reverse

*Attraction:* nothing breaks.
*Fails because* dotted keys need `:'menu.play'`, and the shorter path stays
hardcoded. That fails requirement 1.

### Lazy per-locale loading

*Attraction:* only the current locale in memory.
*Fails because* game text is kilobytes, a language menu wants every language's
own name, and it puts a load on the switch path.

### `I18n` reading the locale directory itself

*Attraction:* works identically in headless specs and the game.
*Fails because* it opens a second file-access seam beside the asset manager
(decision 5), and the method would be there for a game to call. Headless specs,
which have no asset manager, read the files themselves: through spec support in
this repository, and through one generated line in a new project's
`spec_helper.rb`. In both places the line is written for the user rather than
remembered by them.
