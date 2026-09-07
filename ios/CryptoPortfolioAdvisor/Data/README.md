# Data

This directory contains data-layer implementations that depend inward on Domain models.

Phase 4 adds the SwiftData persistence implementation under `Persistence/`. SwiftData entities
remain internal to that boundary and are explicitly mapped to plain persisted draft values or
Domain snapshots. A `ModelActor` owns its `ModelContext`, so contexts and model objects do not
cross arbitrary tasks.

Phase 5 adds complete and ID-based snapshot queries. Complete results are sorted newest first,
with UUID as a deterministic secondary key, before leaving the persistence boundary.

No networking implementation exists yet.
