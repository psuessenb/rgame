---
name: write-skill
description: How to write or edit a skill under .claude/skills — the minimal version that still changes what gets done, a test for what to cut, and the short list of what to keep. Use whenever creating a skill, editing or extending one, or reviewing one that has grown.
---

# Writing a skill

A skill earns its place by changing what gets done. **Write the minimal version
that still does that.** Every line a reader would have followed anyway dilutes
the ones they would not. Its prose follows
[write-prose](../write-prose/SKILL.md).

Apply this to each line, not to the skill as a whole:

> **Would the work come out the same without it?** Then cut it.

## Cut

- **An instruction describing the obvious default** — what anyone competent does
  unprompted.
- **An example of a rule already stated plainly.** Unless it carries something
  the rule cannot state, it is decoration.
- **A second example of the same shape.** The first one landed or it did not.
- **Anything the skill already said**, in another section or another wording.
- **Anything CLAUDE.md or another skill says.** Link to it instead.
- **Prose that enumerates cases.** That is a table.
- **Rationale nobody disputes.** Justify a rule that looks wrong, not one that
  looks obvious.
- **A description of a file format the reader can open and see.**
- **A closing summary.** The skill is already the summary.
- **"Be careful", "consider", "it is important to".** Advice with no action in
  it is not an instruction.

## Keep

What a reader gets wrong without it:

- **The counterintuitive.** The rule whose payoff is the opposite of what it
  looks like.
- **A rule that stops a mistake that actually happened.** Name the mistake in a
  clause; a rule with a scar gets followed.
- **The exact command, path, name or number** — anything otherwise looked up.
- **The counterweight.** What the rule does *not* cover. A strong rule with no
  stated limit gets over-applied.

Length is a symptom, not the target. A long skill of load-bearing lines is
correct; a short one that changed nothing is not.

## Editing one

The same test, plus the one that only applies to edits: **new material makes old
material redundant.** After adding a section, read its neighbours and cut what it
now duplicates. Skills grow by accretion and nothing shrinks them by itself.

## The description

The frontmatter `description` decides whether the skill is found at all. State
the conditions that should trigger it, not a summary of what it contains.
