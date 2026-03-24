---
description: Create or update the project constitution with test-first development
  principles and TDD enforcement
handoffs:
- label: Build Specification
  agent: speckit.specify
  prompt: Implement the feature specification based on the updated constitution. I
    want to build...
---


<!-- Source: spec-as-code -->
## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

**REQUIRED SKILLS**: Launch the `/using-superpowers` skill at the start of your work. This will help you structure this complicated and long task. **REMEMBER**: You are the orchestrator and planner, and your job is orchestrate the sub-agents that actually perform this work.

## Outline

You are updating the project constitution at `.specify/memory/constitution.md`. This file governs ALL subsequent development and MUST be treated as the source of truth.

**CRITICAL**: This constitution emphasizes **Test-First Development (TDD)**. Every feature, every user story, every task MUST have a corresponding test BEFORE implementation begins. A task is NOT complete until its test passes.

### Execution Flow

1. Load the existing constitution at `.specify/memory/constitution.md`
   - If missing, initialize from `.specify/templates/constitution-template.md`

2. **IDENTIFY all placeholder tokens** of the form `[ALL_CAPS_IDENTIFIER]`
   - Count them and confirm with user if the numbers match expectations

3. **Collect/derive values** for placeholders:
   - User input takes priority
   - Infer from existing repo context
   - `CONSTITUTION_VERSION` increments per semantic versioning:
     - MAJOR: Backward-incompatible governance changes
     - MINOR: New principles or materially expanded guidance
     - PATCH: Clarifications and non-semantic refinements

4. **Draft the updated constitution**:
   - Replace ALL placeholders with concrete text
   - Each principle MUST have: name, declarative rule, rationale
   - **TDD Principle (REQUIRED)**: Must state that test-first is non-negotiable
   - Include testing standards: acceptance tests, integration tests, unit tests
   - Include quality gates: tests MUST pass before task completion

5. **Identify Constitution Expert Owners**:
   - Analyze ALL articles/sections in the drafted constitution
   - Group articles by domain.
   - Determine the optimal division among **2 to 4 expert owners**
   - Each expert MUST own at least one article; an expert can own multiple articles
   - Goal: assign articles so each expert is genuinely qualified to review their owned sections
   - **Each section header MUST indicate its owner**: Right after the section header, add `*(owned by: [Expert Name])*`
     - Example: `### III. Bananas for everybody (NON-NEGOTIABLE) *(owned by: Developer Health Expert)*`

6. **Create Expert Knowledge Bases** (dispatch parallel sub-agents for each expert):
   - Launch `/knowledge-base-from-books` skill for EACH expert
   - Use the **dispatching-parallel-agents** skill: one sub-agent per expert, all running concurrently
   - For EACH expert, provide the following to the knowledge-base-from-books skill:
      - **Expert Role**: The expert's specialization (e.g., "Banana Negotiation Expert", "Pear Comparison Investigator", "Fruits and Microbes Analyst")
      - **Owned Articles**: List exactly which constitution articles this expert will own and review
      - **Review Mandate**: Explain this expert will later review constitution changes and verify work adheres to their expertise
      - **Domain Knowledge**: Any additional context about the expert's domain that should inform reviews
   - Knowledge bases will be created at `.knowledge/<expert-slug>/` with:
     - `SUMMARY.md` - Overview of the expert's domain and owned articles
     - Tutorial files covering the expert's knowledge areas
   - The sub-agent for each expert should use the constitution articles as source material

7. **Run Expert Review** (dispatch parallel sub-agents for each expert):
   - Launch `/knowledge-base-usage` skill for EACH expert
   - Use the **dispatching-parallel-agents** skill: one sub-agent per expert, all running concurrently
   - For EACH expert, provide the following to the knowledge-base-usage skill:
      - **Knowledge Base Name**: The slug used in step 6 (e.g., `banana-negotiation-expert`, `pear-comparison-expert`)
      - **Constitution Text**: The full drafted constitution
      - **Owned Articles**: List of their owned articles for focused review
      - **Review Instruction**: "Review your owned articles. Provide specific, actionable feedback to improve clarity, remove redundancy, and ensure each article is well-formed. You may NOT add new articles - only refine, merge, or clarify existing ones. What you are helping with is a constitution document - it describes strategies and patterns, not precise specifications. You must not name specific technologies, or set specific numbers in your feedback."
   - The knowledge-base-usage skill will read the entire knowledge base, making the sub-agent "become" the expert for review purposes
   - Collect feedback from all experts

8. **Apply Expert Feedback**:
   - Merge feedback into the constitution
   - Apply only refinements that don't add new articles
   - If experts suggest conflicting changes, prioritize the more restrictive interpretation
   - Ensure TDD and test-first remain non-negotiable
   - Changes based on expert feedback must not contain specific specifications. Instead, name patterns and strategies to look out for in the following specification phase. For example, don't say "Test Coverage must be >80%", but say "Test Coverage must be ambitious and regularly measured"

9. **Consistency propagation**:
   - Read `.specify/templates/plan-template.md` - ensure Constitution Check gates align
   - Read `.specify/templates/spec-template.md` - ensure acceptance scenario requirements align
   - Read `.specify/templates/tasks-template.md` - ensure test-first task ordering
   - Read all command files in `.specify/templates/commands/*.md` - verify references

10. **Produce Sync Impact Report** (prepend as HTML comment after update):
    ```html
    <!--
    Sync Impact Report:
    - Version: old → new
    - Modified principles: (old → new)
    - Added sections
    - Removed sections
    - Templates requiring updates: ✅/⚠️ with paths
    -->
    ```

11. **Validation**:
    - Zero unexplained bracket tokens remaining
    - Version line matches report
    - Dates in ISO format (YYYY-MM-DD)
    - Principles use MUST/SHOULD (not vague "should")
    - TDD/test-first is EXPLICITLY stated as non-negotiable

12. **Write** to `.specify/memory/constitution.md`

13. **Output summary**:
    - New version and bump rationale
    - Files requiring manual follow-up
    - Suggested commit message

## TDD Enforcement (CRITICAL)

The constitution MUST include these test-first principles:

### Test-First Development (NON-NEGOTIABLE)
- **RED**: Write the failing test FIRST before any implementation
- **GREEN**: Write minimal code to make the test pass
- **REFACTOR**: Improve code quality while keeping tests passing
- **NEVER**: Write implementation code before its corresponding test
- **ACCEPTANCE TESTS**: Each user story MUST have acceptance tests that validate end-to-end behavior
- **INTEGRATION TESTS**: Cross-component interactions MUST have integration tests
- **UNIT TESTS**: Core business logic MUST have unit tests
- **TASK COMPLETION**: A task is only COMPLETE when its test(s) pass

### Implementation Discipline
- **NO SHORTCUTS**: Do not skip tests to "save time"
- **PROOF OVER ASSERTIONS**: Tests must retrieve real data from the system to PROVE it works, not just assert "OK"
- **TEST COVERAGE**: Every logical component described in the spec MUST have tests
- **PARALLEL TESTING**: Where possible, run tests in parallel to verify no regressions

## Governance

The constitution supersedes all other practices. Amendments require:
1. Documentation of the change
2. Compliance review
3. Migration plan for existing artifacts

**Version**: [CONSTITUTION_VERSION] | **Ratified**: [RATIFICATION_DATE] | **Last Amended**: [LAST_AMENDED_DATE]