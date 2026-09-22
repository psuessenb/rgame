---
name: write-prose
description: The prose style rules for this repository — verbs over nouns, active voice, no weak adjectives or filler, short sentences, no jargon or officialese, front-loaded paragraphs, they/their, no redundancy. Use whenever writing or editing prose someone else reads — docs/api pages, plans under docs/plans, pull request bodies, CHANGELOG.md entries, README.md, the header comment of an example, and the top-level comments on classes, modules and C files.
---

# Writing prose

These rules decide how a sentence reads. They apply to every piece of prose in
this repository that someone other than its author reads:

| Where | What decides the content |
|---|---|
| `docs/api/` | [write-docs](../write-docs/SKILL.md) |
| `docs/plans/` | [write-plan](../write-plan/SKILL.md) |
| pull request bodies | [create-pull-request](../create-pull-request/SKILL.md) |
| an example's header comment | [write-example](../write-example/SKILL.md) |
| top-level comments on classes, modules and C files | CLAUDE.md, "Code comments, documentation and code style" |
| `CHANGELOG.md` | [update-changelog](../update-changelog/SKILL.md) |
| `README.md` | setup and orientation for someone arriving at the project |

The page in the second column says what to write. This one says how to write it.

---

## Style rules

### Use verbs, not nouns

Avoid nominalisation. A verb names the action directly.

| Not | But |
|---|---|
| `Text` performs a re-render of the string only upon a change of a variable. | `Text` renders the string again only when a variable changes. |
| `Timer` is responsible for the accumulation of time. | `Timer` accumulates time. |

### Prefer the active voice

Name who does what. The passive voice hides the actor, and in an engine the actor
is the point.

| Not | But |
|---|---|
| The transform is pushed before `_draw` is called. | `Node2D#draw` pushes the transform, then calls `_draw`. |
| Mistakes were made. | We made mistakes. |

### Cut weak adjectives and adverbs

Delete "very", "really", "basically", "simply", "just", "quite", "actually". If
a sentence needs one to sound true, give it a number or a reason instead.

| Not | But |
|---|---|
| `Text` is really cheap. | `Text` allocates nothing while its variables stay the same. |

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

Read the text once against this list:

- Does each paragraph open with its point?
- Does any sentence run past 20 words, or nest a "which" clause?
- Can you replace a noun with a verb, or a passive with an active?
- Did you delete every "very", "really", "basically", "just", "in order to"?
- Does anything say the same thing twice?
