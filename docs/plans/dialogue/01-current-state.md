# What exists, and what blocks a dialogue

Read at `118660a`. Every finding below comes from reading the file it links, and
the ones tagged *measured* were also run.

## The sketch this plan replaces

Item 4 of
[roadmap-complexity-estimate-v0.5.0.md](../research/roadmap-complexity-estimate-v0.5.0.md)
sized "Dialogue and better text" as the one item needing a plan of its own. Two
of its premises no longer hold, and one was never divided.

- **Text measurement is done.** The estimate waited on it. `Util::Typeface`
  measures and breaks text headless, `Engine::Paragraph` keeps the broken lines
  and groups them into pages, and `UI::Label` draws a page. The wrapping half of
  "better text" is shipped.
- **"A queue of beats, advance on `ui_confirm`" is too small.** A queue does not
  go back, does not branch on a condition, and does not serve a quest. The
  request asks for a graph.
- **Where a conversation has got to and how it is drawn were one item.** They
  are two, and this plan builds them in that order.

## F1. Nothing in the engine is a state machine — *(measured)*

No `@state`, `@mode` or `@phase`, and no `case` over one, in
`lib/rgame/engine/`. The closest things are fixed and small:
[`Button#state`](../../../lib/rgame/engine/ui/button.rb#L149) derives one of three
looks from two flags, and `UI::Menu` is open or closed. Neither has transitions a
caller defines, and neither wants a general machine. The machine therefore
replaces nothing; its two callers are this plan's dialogue and a game's quests.

## F2. Text, paging and translation are ready

| What | Where | What a dialogue gets from it |
|---|---|---|
| `Engine::Text` | [text.rb](../../../lib/rgame/engine/text.rb) | a line, a speaker's name and a response label as keys, with variables, cached until one changes |
| `Engine::Paragraph` | [paragraph.rb](../../../lib/rgame/engine/paragraph.rb) | a line broken to the box's width and grouped into pages; an unchanged read allocates nothing |
| `UI::Label` | [label.rb](../../../lib/rgame/engine/ui/label.rb) | a page drawn and turned; `last_page?` says when the line is finished |
| `I18n` | [i18n.rb](../../../lib/rgame/engine/i18n.rb) | a missing key fails a driven run, so a line left out of `en.yml` cannot reach the screen |

`Paragraph#page` answers the nearest page for an index past the end, because a
language switch can shorten a paragraph while it is shown. A dialogue that
switches language mid-line inherits that for free.

## F3. A menu can list responses, and cannot change them — *(measured)*

`UI::Menu` has `add` and no way to remove a button
([menu.rb](../../../lib/rgame/engine/ui/menu.rb), 290 lines). A dialogue's
responses change at every beat. Either the box builds a new menu per beat, or
the menu learns to drop its buttons. The second is also what an inventory screen
will want, so it belongs to the "extend" pile below.

Three things the menu already does are exactly right:

- **`Stepping` skips a disabled button** as it moves focus
  ([stepping.rb:65](../../../lib/rgame/engine/ui/stepping.rb#L65)). A response
  shown but not available is a disabled button, and nothing new decides that
  focus passes over it.
- **A menu acts only on a press it saw start.** The confirm that finishes a
  line is still down when the responses appear, and the menu will not read it as
  a choice.
- **A menu inherits its player.** Inside a `PlayerLayer`, its `actions` are that
  player's, so two players in two conversations need nothing.

## F4. A clip cannot hide the unrevealed part of a line — *(measured)*

`renderer.clipped` takes window coordinates: `rgame_app_push_clip` pushes the
rectangle as given, untransformed
([app.c:765](../../../ext/rgame_core/app/app.c#L765)). A node draws in local
space and may not read its own position (`Game/DrawInLocalSpace`). So a
typewriter cannot draw the whole line and clip it at the revealed width; it has
to draw a prefix.

Building a prefix on every frame is what `Game/NoNeedlessAllocation` refuses.
Building all of a page's prefixes once, when the page appears, costs little:

| *(measured, Ruby 4.0.5, no YJIT)* | |
|---|---|
| Every prefix of a 43-character line, as frozen Strings | 9 µs, 48 objects |
| Reading one of them 1000 times | 0 objects |
| Measuring every prefix with `Typeface#text_width` instead | 182 µs |

A three-line page costs about 30 µs once. The reveal then indexes an Array.

## F5. Shared state has two homes already, and neither fits flags

- **A system on the root** is how a node reaches something global:
  `node.system(Components::Facts)` would find a store mounted there
  ([docs/api/systems.md](../../api/systems.md)).
- **`Util::SaveFile`** writes one Hash as JSON and reads it back with Symbol
  keys ([save_file.rb:82](../../../lib/rgame/util/save_file.rb#L82)). A Symbol
  *value* comes back a String. A store that accepted Symbol values would restore
  different values than it saved, silently.

Nothing holds a flag that belongs to no object. Every example keeps its state in
the ivars of the node that owns it, which is right for gold and wrong for "the
bridge is down", which three nodes read and none owns.

## F6. Starting a conversation from a zone needs nothing new

The request asked whether this already works. It does. A `BoxCollider` emits
`on_hit` with the other collider when two start to touch
([box_collider.rb:27](../../../lib/rgame/engine/components/box_collider.rb#L27)),
and `CollisionWorld#nearest` answers "which character am I standing next to" for
a conversation started with confirm. The example in step 6 shows both.

## What this resembles: the three piles

**Reuse it.**

- `Engine::Text`, `Engine::Paragraph`, `UI::Label` — every word on screen.
- `UI::Menu`, `UI::TextButton`, `Button#enabled` and `UI::Stepping` — the
  response list, and hiding or disabling what is not available.
- `UI::ShapeStyle` and `UI::NineSliceStyle` — the box's panel, as a button's.
- `PlayerLayer` — whose conversation it is, and where on screen.
- `Signal::DSL` — `on_changed` on a machine, `on_beat` and `on_ended` on a
  dialogue.
- `Util::SaveFile` — the facts' `to_h` goes into it as it is, carrying every
  named machine with it. A game's settings go into a second file.
- The accumulate-in-`update`, index-in-`draw` shape of `Animator` and `Timer` —
  the reveal.

**Extend or generalise it.**

- **`UI::Label` gains a reveal.** A typewriter is a label that shows less than a
  page. Building a second text widget beside it would duplicate paging,
  alignment and the language switch, and answer the same question — "which
  characters of this page are drawn" — twice.
- **`UI::Menu` learns to drop its buttons** (F3).

**Genuinely new.**

- **`Engine::StateGraph` and `Engine::StateMachine`.** F1 counted: nothing in
  the engine has states a caller defines. The nearest shape, `SceneStack`, is a
  stack, and a conversation that goes back to a question is a cycle.
- **`Components::Facts`.** F5: no existing store holds a flag no object owns.
- **`Engine::Dialogue`** and **`UI::DialogueBox`**. The first is a state machine
  with words; the second a view over it.

**The composition nothing exercises yet.** Two new systems sit side by side
here: a dialogue and a quest, both on the machine, both reading the facts. Of
the 29 projects in the repository, the number with either is zero. So the first
test of the dialogue layer is a conversation that reads a quest's stage and
moves it on, not a conversation alone. See step 2.
