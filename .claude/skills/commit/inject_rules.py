#!/usr/bin/env python3
"""PreToolUse hook: put the commit-message rules in front of every git commit.

Claude Code pipes the pending tool call in on stdin. When the command is a git
commit, this prints the body of SKILL.md back as additionalContext, so the rules
are in the model's context at the moment the message is written rather than
relying on the skill being noticed. Anything else prints nothing and the tool
call proceeds untouched.

SKILL.md is the single source of the rules; its YAML frontmatter is stripped
here so only the prose is injected.
"""

import json
import os
import re
import sys

SKILL = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'SKILL.md')

# Matches `git commit`, and also `git -C dir commit`, `git commit --amend`, and
# a commit anywhere in a compound command such as `make test && git commit`.
IS_GIT_COMMIT = re.compile(r'\bgit\b[^\n;&|]*\bcommit\b')


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    command = (payload.get('tool_input') or {}).get('command') or ''
    if not IS_GIT_COMMIT.search(command):
        return 0

    with open(SKILL, encoding='utf-8') as handle:
        text = handle.read()
    # Drop the frontmatter block: everything up to and including the second ---.
    body = re.sub(r'\A---\n.*?\n---\n', '', text, flags=re.DOTALL)

    json.dump({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'additionalContext': body,
        },
    }, sys.stdout)
    return 0


if __name__ == '__main__':
    sys.exit(main())
