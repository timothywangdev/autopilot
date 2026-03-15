---
description: Initialize autopilot in current project. Creates .specify/ directory with templates and constitution.

evals:
  - prompt: "/autopilot:init"
    expect: |
      - Creates .specify/ directory
      - Creates .specify/memory/constitution.md
      - Creates .specify/templates/ with all template files
      - Creates specs/ directory
      - Shows success message with next steps

  - prompt: "/autopilot:init"
    setup: "mkdir -p .specify/templates && echo 'existing' > .specify/templates/spec-template.md"
    expect: |
      - Detects existing .specify/ directory
      - Asks user about overwrite vs skip
      - Does NOT overwrite without confirmation

  - prompt: "/autopilot:init"
    setup: "mkdir -p .specify && touch .specify/memory/constitution.md"
    expect: |
      - Handles partial initialization gracefully
      - Creates missing files only
      - Reports what was created vs skipped
---

## Initialization

Initialize autopilot spec-driven development in the current project.

## Steps

1. **Check existing setup**: If `.specify/` already exists, ask user if they want to overwrite or skip.

2. **Create directory structure**:
   ```
   .specify/
   ├── memory/
   │   └── constitution.md
   └── templates/
       ├── spec-template.md
       ├── plan-template.md
       ├── tasks-template.md
       ├── checklist-template.md
       └── agent-file-template.md
   ```

3. **Copy templates**: Copy all template files from the autopilot plugin's `templates/` directory to `.specify/templates/`.

4. **Copy constitution**: Copy constitution template to `.specify/memory/constitution.md`.

5. **Create specs directory**: Create `specs/` directory for feature specifications if it doesn't exist.

6. **Update .gitignore** (optional): Ask user if they want to add `.specify/memory/` to `.gitignore` (constitution may contain project-specific decisions).

7. **Confirm setup**:
   ```
   Autopilot initialized successfully.

   Structure created:
     .specify/templates/    - Specification templates
     .specify/memory/       - Project constitution
     specs/                 - Feature specifications

   Next steps:
     1. Run /autopilot.constitution to define project principles
     2. Create a plan file for your feature
     3. Run /autopilot.full <plan-file> to implement
   ```

## Template Source

Templates are bundled with the autopilot plugin at:
```
~/.claude/plugins/autopilot/templates/
```

Or if installed via symlink during development:
```
~/projects/autopilot/templates/
```

Use `$CLAUDE_PLUGIN_ROOT` environment variable if available to locate templates dynamically.
