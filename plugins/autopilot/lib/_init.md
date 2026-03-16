---
description: Initialize autopilot in current project. Creates .autopilot/ directory with templates and context.
scripts:
  sh: scripts/bash/init-project.sh
---

## Initialization

Initialize autopilot spec-driven development in the current project.

## Execution

1. **Run the init script**:
   ```bash
   plugins/autopilot/scripts/bash/init-project.sh
   ```

   Or with force flag to reinitialize:
   ```bash
   plugins/autopilot/scripts/bash/init-project.sh --force
   ```

2. **Parse the JSON output**:
   - `status`: "success" | "exists"
   - `directories`: paths to created directories
   - `created`: list of files created
   - `skipped`: list of files skipped (already existed)

3. **Handle "exists" status**: If `.autopilot/` already exists, ask user if they want to reinitialize with `--force`.

4. **Report results**:
   ```
   Autopilot initialized successfully.

   Structure created:
     CLAUDE.md              - Constitution (project principles)
     .autopilot/context.md  - Active tech stack (auto-updated)
     .autopilot/templates/  - Specification templates
     specs/                 - Feature specifications

   Next steps:
     1. Edit CLAUDE.md to define project principles
     2. Create a plan file for your feature
     3. Run /autopilot:loop <plan-file> to implement
   ```

## Directory Structure

```
CLAUDE.md                    # Constitution (static principles, user-maintained)

.autopilot/
├── context.md               # Active context (tech stack, auto-updated from plans)
└── templates/
    ├── spec-template.md     # Feature specification template
    ├── plan-template.md     # Implementation plan template
    ├── tasks-template.md    # Task breakdown template
    └── checklist-template.md

specs/                       # Feature directories go here
└── NNN-feature-name/
    ├── spec.md
    ├── plan.md
    ├── tasks.md
    └── .workflow-state.json
```

## Template Source

Templates come from the spec-kit submodule bundled with autopilot:
```
vendor/spec-kit/templates/
```
