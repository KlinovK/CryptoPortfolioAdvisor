# Development Rules

These rules apply to all future Codex sessions in this repository.

1. Inspect the existing architecture and relevant code before making changes.
2. Implement only the phase and scope explicitly requested by the user.
3. Do not implement future features early, even when their interfaces are documented.
4. Prefer small, reviewable changes over broad refactors.
5. Preserve the documented dependency direction: outer layers may depend on inner layers,
   never the reverse.
6. Do not use Combine. Use Swift Structured Concurrency and `async`/`await` only.
7. Do not use `DispatchQueue` for business logic.
8. Never call the OpenAI API from the iOS application. OpenAI credentials and calls belong
   exclusively on the backend.
9. Keep deterministic calculations and validations outside the LLM.
10. Keep features dependency-injected and unit-testable.
11. Run relevant tests after every change. Run configured formatting and lint checks when
    available.
12. Report all changed files at handoff.
13. Report architectural decisions made during the change.
14. Report remaining TODOs without implementing them unless requested.
15. Do not silently introduce dependencies. Explain and justify every new dependency.

