# Data

The active `API/ATA/` layer implements authenticated ATA HTTP V1 and maps strict transport DTOs
to ATA domain models. `Credentials/` stores the bearer token in Keychain. Neither layer uses the
older CPA analysis types.

`API/` outside `ATA/` and `Persistence/` are retained CPA prototype implementations for legacy
tests and existing on-disk SwiftData compatibility. The active app does not construct their
client or ModelContainer, read their data, or use them as an ATA fallback.
