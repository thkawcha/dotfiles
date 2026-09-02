---
name: mermaid-diagrams
description: >-
  Create, edit, validate, preview, repair, or visualize Mermaid diagrams with
  the MermaidChart VS Code extension. Use for flowcharts, sequence diagrams,
  ER diagrams, Docker diagrams, C4 architecture, dependency graphs, and code
  ownership diagrams.
---

# Mermaid Diagrams

Use the Mermaid VS Code extension tools and commands whenever the user asks to
create, edit, or visualize a diagram.

## Workflow

1. Determine the diagram type and generate Mermaid syntax.
2. Write the diagram to a `.mmd` file in the current project.
3. Validate the syntax, including the first-line keyword, arrow types, and
   balanced brackets.
4. Preview the result through the Mermaid extension.

## LM tools

Call these tools for every diagram interaction:

- `mermaid-diagram-validator`: validate Mermaid syntax before presenting it.
- `mermaid-diagram-preview`: render a live preview after generating it.
- `get-syntax-docs-mermaid`: fetch syntax documentation before generating an
  unfamiliar diagram type.

## VS Code commands

Invoke commands through the Command Palette or VS Code command API. Do not
invent command IDs. Prefer writing or editing `.mmd` files when no command is
needed.

### Editing and preview

- **Preview** (`mermaidChart.preview`): preview the active `.mmd` or `.mermaid`
  editor.
- **Create Diagram** (`mermaidChart.createMermaidFile`): create a demo flowchart
  and open its preview side by side.
- **Repair Diagram** (`mermaidChart.repairDiagram`): repair the active diagram
  with Mermaid AI. Tell the user before running it because it uses Mermaid AI
  credits.
- **Improve Diagram** (`mermaidChart.improveDiagram`): suggest layout and style
  variants with Copilot or the LM API.

### Diagram generation

- **Generate Diagram from Code** (`mermaidChart.generateDiagramFromCode`)
- **Generate ER Diagram** (`mermaidChart.generateERDiagram`)
- **Generate Docker Diagram** (`mermaidChart.generateDockerDiagram`)
- **Open AI Chat** (`mermaidChart.openCopilotChat`)

### Mermaid Sync review

- **Review Mermaid Sync** (`mermaidChart.reviewAppCommits`): start or open the
  review flow for diagrams updated by the Mermaid Chart GitHub Sync app or a
  pre-commit regeneration.
- **Regenerate with Mermaid AI**
  (`mermaidChart.regenerateDiagramWithMermaidAI`): regenerate from source
  references. Do not manually rewrite diagrams managed by this workflow; use
  the extension UI to accept, reject, or inspect diffs.

### Install or update

- **MermaidChart: Install AI Skills...** (`mermaidChart.installAiSkills`)

## Mermaid Chart slash commands

| Command | Purpose |
| --- | --- |
| `/generate_diagram_from_code` | General diagram from any source file |
| `/generate_execution_sequence` | Sequence diagram from code flow |
| `/generate_er_diagram` | ER diagram from schema or models |
| `/generate_docker_diagram` | Architecture from Dockerfiles |
| `/generate_c4_topdown_architecture` | C4 top-down architecture |
| `/analyze_code_ownership` | Code ownership diagram |
| `/generate_dependency_diagram` | Dependency or security visualization |

## Rules

1. Always call `mermaid-diagram-validator` before showing a diagram.
2. Always call `mermaid-diagram-preview` after generating a diagram.
3. Use `get-syntax-docs-mermaid` before generating an unfamiliar diagram type.
4. Prefer the Mermaid Chart slash commands for complex generation.
5. Write diagrams to `.mmd` files; never return unvalidated Mermaid syntax.
6. Warn the user before using Repair because it consumes Mermaid AI credits.
7. Cooperate with the Sync workflow; do not manually regenerate managed
   diagrams.

## Documentation

See https://marketplace.visualstudio.com/items?itemName=MermaidChart.vscode-mermaid-chart
for more commands and features.
