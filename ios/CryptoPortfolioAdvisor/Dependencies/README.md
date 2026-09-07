# Dependencies

This directory contains dependency abstractions used by Features for external capabilities.

Phase 4 adds `PortfolioPersistenceClient`, a small async, Sendable-safe TCA dependency for
loading and saving the current draft and immutable snapshots. The live SwiftData implementation
is composed at the app root; tests inject controlled closures or an in-memory implementation.

Phase 5 extends the same focused client with all-snapshot and ID-based snapshot reads. No generic
repository abstraction is introduced.
