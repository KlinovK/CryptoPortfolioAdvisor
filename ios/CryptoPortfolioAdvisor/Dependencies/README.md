# Dependencies

The active app composes only `ATAClient` for authenticated portfolio/analysis HTTP operations and
`CredentialStore` for Keychain-backed bearer credentials. ATA feature tests inject fakes.

`PortfolioAnalysisClient` and `PortfolioPersistenceClient` remain for isolated CPA prototype
source and tests. They are not registered at the app composition root, and their data is never an
active ATA authority or fallback.
