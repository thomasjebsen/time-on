# Workflow

## TDD Policy

**Moderate** — tests are encouraged but not a blocker. Write tests for important logic; don't let missing tests hold up progress.

## Commit Strategy

Descriptive commit messages, no required format. Messages should clearly explain what changed and why.

## Code Review

Optional / self-review OK. No mandatory review gates.

## Verification Checkpoints

Manual verification required **only at track completion**. Intermediate phases and tasks do not require explicit sign-off.

## Task Lifecycle

1. Create track with `/conductor:new-track`
2. Implement tasks with `/conductor:implement`
3. Verify at track completion
4. Archive completed tracks
