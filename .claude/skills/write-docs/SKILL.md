---
name: write-docs
description: How to write reference documentation under docs/api — what a page may say (the current code, nothing else), code examples that stand on their own, and the prose style rules (verbs over nouns, active voice, short sentences, no filler, no officialese, front-loaded paragraphs, they/their). Use whenever creating or editing a page in docs/api/, when a code change needs its documentation updated, or when folding a finished plan back into the documentation.
---

# Writing documentation

Reference documentation lives in `docs/api/`. It ships inside the gem, so its
reader has installed rgame and has nothing else. Write every page for that
reader. They have only the current code and took no part in writing it. The page
should help them understand that code and use it.

The top-level `README.md` and `ext/README.md` stay where they are. They cover
setup and orientation, not reference material.

Plans under `docs/plans/` follow different rules. See
[write-plan](../write-plan/SKILL.md).

---

## When to write it

Write documentation together with the code. A change to public behaviour is not
done until its `docs/api/` page describes it. A new page also gets a row in the
index table of `docs/api/README.md`.

Some pages end in a "What this is not" section. When a change fills one of those
gaps, trim the list so it names only what is still missing.

## What a page may say

**Describe the code as it is now.** Do not describe how it got there. A page never
mentions:

- prompts, or decisions taken in them;
- implementations that no longer exist ("used to", "replaces the earlier…",
  "now", "still");
- throwaway example code written while building the feature;
- other game engines or games. Prior art belongs in plans, where it helps. The
  reference documentation leaves it out.

**Make every code example stand on its own.** A reader must understand it without
outside context. It must also run against the current code. Before you commit a
page, check each example against the classes and signatures it names. If a
snippet can run headless, run it:

```
ruby -Ilib -e 'require "rgame"; ...'
```

Examples follow the same rules as the engine's code. They build labels with
`Engine::CachedLabel`, draw in local space, and never name `RGame::Core` from
engine-layer code.

---

## Style rules

### Use verbs, not nouns

Avoid nominalisation. A verb names the action directly.

| Not | But |
|---|---|
| `CachedLabel` performs a rebuild of the string only upon a change of the value. | `CachedLabel` rebuilds the string only when the value changes. |
| `Timer` is responsible for the accumulation of time. | `Timer` accumulates time. |

### Prefer the active voice

Name who does what. The passive voice hides the actor, and in an engine the actor
is the point.

| Not | But |
|---|---|
| The transform is pushed before `on_draw` is called. | `Node2D#draw` pushes the transform, then calls `on_draw`. |
| Mistakes were made. | We made mistakes. |

### Cut weak adjectives and adverbs

Delete "very", "really", "basically", "simply", "just", "quite", "actually". If
a sentence needs one to sound true, give it a number or a reason instead.

| Not | But |
|---|---|
| `CachedLabel` is really cheap. | `CachedLabel` allocates nothing while the value stays the same. |

### Keep sentences short

Aim for 15 to 20 words at most. Avoid nested sentences. Split "which" and "who"
clauses into sentences of their own.

| Not | But |
|---|---|
| The camera, which follows a target that the player controls, clamps to the world bounds, which the tile map provides. | The camera follows a target. It clamps to the world bounds the tile map provides. |

### Avoid jargon and buzzwords

Delete "synergy", "leverage", "going forward", "robust", "seamless". Write "use",
not "utilize".

### Be clear and concise

Get to the point in the first sentence. Do not announce what a section is about
to say; say it.

| Not | But |
|---|---|
| In this section we will take a look at how timers work. | A `Timer` accumulates time. Its owner decides what each interval means. |

### Avoid officialese

| Not | But |
|---|---|
| in order to | to |
| subsequent to | after |
| prior to | before |
| in the event that | if |
| with regard to | about |
| a number of | some, or the number |
| is able to | can |

### Front-load paragraphs

Put the result, the rule or the answer first. The reasons follow. A reader who
stops after one sentence should still leave with the thing they came for.

| Not | But |
|---|---|
| Because depth testing and blending cannot be combined, and UI is often translucent, the renderer sorts on the CPU. | The renderer sorts draws by z on the CPU. Depth testing cannot be combined with alpha blending, and UI is often translucent. |

### Use gender-neutral language

Write "they/their" for a player, a user or a game author. Do not write "he or
she" or "s/he". Plural forms often read better still: "players", not "a player".

### Avoid redundancy

Say each thing once. Do not repeat a heading in the first sentence below it. Do
not restate a code example in prose line by line. Do not end a section by
summarising what it just said.

---

## Before you finish

Read the page once against this list:

- Does any sentence describe the past, a prompt or another engine?
- Does every code example run against the current code, without outside context?
- Does each paragraph open with its point?
- Does any sentence run past 20 words, or nest a "which" clause?
- Can you replace a noun with a verb, or a passive with an active?
- Did you delete every "very", "really", "basically", "in order to"?
- Does `docs/api/README.md` list the page?
