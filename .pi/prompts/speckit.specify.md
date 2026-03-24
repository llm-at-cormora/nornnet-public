---
description: Define feature specifications with acceptance scenarios that expose backend
  complexity through test scaffolding
handoffs:
- label: Create Plan
  agent: speckit.plan
  prompt: Create technical implementation plan based on the specification
- label: Clarify Requirements
  agent: speckit.clarify
  prompt: Clarify underspecified areas in the requirements
scripts:
  sh: scripts/bash/check-prerequisites.sh --json
  ps: scripts/powershell/check-prerequisites.ps1 -Json
---


<!-- Source: spec-as-code -->
## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Overview

You are creating a feature specification at `.specify/specs/[###-feature-name]/spec.md`. This specification:

1. Focuses on **WHAT** and **WHY**, not the **HOW**
2. Describes **acceptance scenarios** that hide backend complexity
3. Exposes **logical components** through test scaffolding (discovered in plan phase)
4. Follows the principle: "The spec tells WHAT, the plan tells HOW, the tests PROVE it"

## Pre-Execution Checks

Check for extension hooks (before specification):
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_specify` key
- Filter out hooks where `enabled` is explicitly `false`.
- For each remaining hook, output the appropriate block (optional or mandatory)
- If no hooks registered or file missing, skip silently

## Outline

1. **Setup**: Run `{SCRIPT}` from repo root to get FEATURE_SPEC, SPECS_DIR, BRANCH

2. **Load context**: Read `.specify/memory/constitution.md` to understand project principles

3. **Execute specification workflow**:

### Phase 1: Requirements Gathering

> **Pattern Reference**: This phase follows the same discovery approach as constitution Steps 5-8, 
> where experts are determined based on project content.

**Focus on user needs, not technical implementation**

1. **Identify the problem being solved**
   - What user pain does this solve?
   - Who are the stakeholders?
   - What are the success criteria?

2. **Define acceptance scenarios (NOT implementation)**
   - Write scenarios as **black-box tests**
   - Each scenario describes observable behavior
   - Hide internal complexity (kitchen operations, service protocols, staff workflows)
   - Example: "Guest checks into hotel and receives room key" NOT "Front desk queries room database and dispatches bellhop service"

3. **Specify logical components (at domain level)**
   - Describe what the system DOES (domain verbs)
   - Do NOT specify how it does it (no process machinery)
   - Components emerge from acceptance scenarios

4. **Define quality attributes**
   - Performance requirements (if any)
   - Security requirements (if any)
   - Usability requirements (if any)

5. **Identify Cross-Cutting concerns**
    - Which concerns span across the entire system?

### Phase 2: User Stories with Traceability

Each user story MUST have:

1. **ID** (e.g., US1, US2, US3)
2. **Title** (concise description)
3. **Priority** (P1 = "cruial even in PoC", P2 = "expected in MVP", P3 = "need-to-have", P4 = "nice-to-have")
4. **Story text** (As a... I want... so that...)
5. **Acceptance criteria** (verifiable, testable conditions)
6. **Traceability** (which acceptance scenarios this story supports)

### Phase 3: Acceptance Scenario Mapping

For each acceptance scenario:

1. List which **logical components** it exercises
2. List which **user stories** it supports
3. Note any **cross-cutting concerns** it triggers

**IMPORTANT**: The acceptance scenarios hide backend complexity. The plan phase will "uncover" the underlying operations through the test scaffolding research.

## Spec Template Structure

Use `.specify/templates/spec-template.md` as the document scaffold. The specification MUST include:

### 1. Feature Overview
- Problem statement
- Success criteria
- Scope (in/out)

### 2. User Stories
- Organized by priority (P1, P2, P3, P4)
- Each with acceptance criteria

### 3. Acceptance Scenarios
- **Format**: Given-When-Then
- **Black-box**: Describe external behavior only
- **Verifiable**: Must be testable
- **Independent**: Can be implemented/tested independently

### 4. Logical Components (Domain Level)

**A logical component represents a distinct capability or responsibility area that emerges from the acceptance scenarios. It answers: "What does the system need to BE able to DO?"**

**Characteristics of a Logical Component:**
- Emerges from acceptance scenarios (what the system MUST do)
- Identified by domain verbs: manages, processes, handles, coordinates, tracks
- Each component has a clear owner (a domain expert)
- Components collaborate to fulfill acceptance scenarios

**Example:**
If acceptance scenarios mention "guest boards ride", "guest purchases food", "guest enters park", the logical components might be:
- **Ride Operations** (manages ride availability and boarding)
- **Food & Beverage Services** (processes food orders and fulfillment)
- **Entry Gate Services** (handles ticket validation and entry)
- **Guest Services** (coordinates lost children, complaints, refunds)

### 5. Cross-Cutting Concerns

**A cross-cutting concern represents a quality or constraint that SPANS across all logical components. It answers: "What must ALL parts of the system CONSIDER?"**

**Characteristics of a Cross-Cutting Concern:**
- Applies to ALL logical components, not just one
- Often represents non-functional requirements (safety, compliance, reliability)
- Does NOT "own" any domain functionality
- Must be considered by every component

**Why is "Park Sanitation" a Cross-Cutting Concern but "Ride Operations" is not?**
- **Ride Operations** is a logical component because it "owns" the capability of managing rides. It is responsible for making rides work.
- **Park Sanitation** is NOT a logical component because it does not "own" any capability. Instead, it is a constraint that ALL components must consider: Ride Operations must maintain cleanliness, Food & Beverage must maintain cleanliness, Entry Gate must maintain cleanliness.

**Example:**
- **Park Sanitation** is a cross-cutting concern because EVERY department must maintain cleanliness standards
- **Supply Provisioning** is a cross-cutting concern because it affects how ALL departments receive their materials
- **Uniform Dress Code** is a cross-cutting concern because ALL staff must meet appearance standards

If the identified quality attributes are "Cleanliness" and "Operational Readiness", the cross-cutting concerns might be:
- **Park Sanitation** (all departments must maintain cleanliness standards)
- **Supply Provisioning** (all departments must receive materials and supplies on time) 

### 6. Acceptance Checklist
A review checklist to validate spec quality:
- [ ] Each user story has acceptance criteria
- [ ] Each acceptance criterion is testable
- [ ] Acceptance scenarios cover all user stories
- [ ] No technology/implementation details in acceptance scenarios
- [ ] Logical components are at domain level (not technical)

## Validation Before Writing

Before writing the specification, perform expert validation following the constitution pattern:

### Phase 1: Load and Analyze Draft

1. **Load the drafted specification** from `.specify/specs/[###-feature-name]/spec.md`
2. **Parse Section 4 (Logical Components)**: Extract department names and responsibilities
3. **Parse Section 5 (Cross-Cutting Concerns)**: Extract concern types

### Phase 2: Determine Expert Fields

Based on SPEC CONTENT, determine expert fields:

**For Logical Components**, identify 2 experts that cover the identified domains. For example if the domains are "Ride Operations", "Guest Services", "Food & Beverage", "Ticketing", two experts that cover all of areas might be "Roller Coaster Engineering Expert" and "Theme Park Guest Experience Expert".
Update the list of domains, which of the 2 experts is the DOMAIN OWNER. Every domain MUST have a domain owner. Example: Ride Operations → Roller Coaster Engineering Expert, Guest Services → Theme Park Guest Experience Expert.

**For Cross-Cutting Concerns**, identify 2 experts based on concern types. For example, if the cross cutting concerns are "Park Sanitation", "Supply Provisioning", "Uniform Dress Code", "Staff Scheduling", two experts that cover all of areas might be "Chief Custodial Services Expert" and "Supply Chain Logistics Expert".
In the list of cross-cutting concern, assign the appropriate expert to EACH OF THE CROSS-CUTTING CONCERNS. Every cross-cutting concern MUST have an owner. Example: Park Sanitation → Chief Custodial Services Expert, Supply Provisioning → Supply Chain Logistics Expert.


### Phase 3: Create Expert Knowledge Bases

For each of the 4 experts, dispatch parallel sub-agents using `/knowledge-base-from-books` skill:

```
Task: Create expert knowledge base for [Expert Name]

Skill: /knowledge-base-from-books

Expert Role: [Role description based on determined field]
Owned Sections: Section 4 (Logical Components) and/or Section 5 (Cross-Cutting Concerns)
Review Mandate: This expert will review specification sections to verify domain correctness, identify missing concerns, and ensure components are properly scoped
Domain Knowledge: [Infer from spec content]
Knowledge Base Location: .knowledge/<expert-slug>/
```

### Phase 4: Run Expert Reviews

For each of the 4 experts, dispatch parallel sub-agents using `/knowledge-base-usage` skill:

```
Task: Review specification with [Expert Name]

Skill: /knowledge-base-usage

Knowledge Base Name: <expert-slug>
Content to Review: [Full text of Section 4 or Section 5]
Owned Sections: [Which section(s) this expert reviews]
Review Instruction: Review your owned sections. Provide specific, actionable feedback on:
1. Component completeness - are all necessary components identified?
2. Responsibility clarity - are component boundaries clear?
3. Missing concerns - are there gaps in coverage?
4. Scope alignment - do components match the acceptance scenarios?
You are reviewing a specification document - provide feedback as patterns/strategies, NOT specific technologies or numbers.
```

### Phase 5: Apply Expert Feedback

1. Collect feedback from all 4 experts
2. Merge feedback into specification updates
3. Apply only refinements that enhance clarity and completeness
4. Ensure changes do NOT introduce technology choices (those come in Plan phase)
5. Changes should be patterns/strategies only, no specific implementations

### Phase 6: Redo Acceptance Checklist

After applying expert feedback, re-validate the specification:

1. Re-run Section 7 Acceptance Checklist
2. Verify all user stories have acceptance criteria
3. Verify acceptance criteria are testable (Given-When-Then format)
4. Verify logical components are domain-level (no implementation hints)
5. Verify cross-cutting concerns cover all quality attributes
6. Verify no technology choices remain in the document

### Key Constraints

- **Spec must NOT contain specific technologies or numbers**
- **Expert feedback should only suggest patterns/strategies**
- **All work must be done via sub-agents** (never do expert review yourself)

## Output

Write to `.specify/specs/[###-feature-name]/spec.md`

Report:
- Feature name and branch
- User story count (by priority)
- Acceptance scenario count
- Key logical components identified
- Suggested next step: `/speckit.plan`

## Post-Execution Hooks

After spec creation, check for `hooks.after_specify` in `.specify/extensions.yml` and execute appropriately.