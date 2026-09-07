import Foundation
import SwiftData

enum PersistenceContainerFactory {
    static func makeModelContainer(
        isStoredInMemoryOnly: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema([
            DashboardDraftEntity.self,
            PortfolioSnapshotEntity.self,
            PortfolioAnalysisEntity.self,
        ])
        let configuration = ModelConfiguration(
            "CryptoPortfolioAdvisor",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            groupContainer: .none,
            cloudKitDatabase: .none
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

enum PersistenceStoreError: Error, Equatable, Sendable {
    case duplicateSnapshotID(UUID)
    case conflictingAnalysisID(UUID)
}

@ModelActor
actor PersistenceStore {
    func loadDashboardDraft() throws -> PersistedDashboardDraft? {
        let entities = try modelContext.fetch(FetchDescriptor<DashboardDraftEntity>())
        guard let entity = entities.first else {
            return nil
        }

        return try PersistenceMapper.decodeDashboardDraft(entity.payload)
    }

    func saveDashboardDraft(_ draft: PersistedDashboardDraft) throws {
        let payload = try PersistenceMapper.encodeDashboardDraft(draft)
        let entities = try modelContext.fetch(FetchDescriptor<DashboardDraftEntity>())

        if let current = entities.first {
            current.payload = payload
            for duplicate in entities.dropFirst() {
                modelContext.delete(duplicate)
            }
        } else {
            modelContext.insert(DashboardDraftEntity(payload: payload))
        }

        try modelContext.save()
    }

    func saveSnapshot(_ snapshot: PortfolioSnapshot) throws {
        let entities = try modelContext.fetch(FetchDescriptor<PortfolioSnapshotEntity>())
        guard !entities.contains(where: { $0.id == snapshot.id }) else {
            throw PersistenceStoreError.duplicateSnapshotID(snapshot.id)
        }

        let payload = try PersistenceMapper.encodeSnapshot(snapshot)
        modelContext.insert(
            PortfolioSnapshotEntity(
                id: snapshot.id,
                createdAt: snapshot.createdAt,
                payload: payload
            )
        )
        try modelContext.save()
    }

    func loadLatestSnapshot() throws -> PortfolioSnapshot? {
        try loadSnapshots().first
    }

    func loadSnapshots() throws -> [PortfolioSnapshot] {
        let entities = try modelContext.fetch(FetchDescriptor<PortfolioSnapshotEntity>())
        let snapshots = try entities.map { entity in
            try PersistenceMapper.decodeSnapshot(
                id: entity.id,
                createdAt: entity.createdAt,
                payload: entity.payload
            )
        }

        return snapshots.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func loadSnapshot(id: UUID) throws -> PortfolioSnapshot? {
        let requestedID = id
        var descriptor = FetchDescriptor<PortfolioSnapshotEntity>(
            predicate: #Predicate { entity in
                entity.id == requestedID
            }
        )
        descriptor.fetchLimit = 1

        guard let entity = try modelContext.fetch(descriptor).first else {
            return nil
        }
        return try PersistenceMapper.decodeSnapshot(
            id: entity.id,
            createdAt: entity.createdAt,
            payload: entity.payload
        )
    }

    func saveAnalysis(_ analysis: PortfolioAnalysis) throws {
        let requestedID = analysis.id
        var descriptor = FetchDescriptor<PortfolioAnalysisEntity>(
            predicate: #Predicate { entity in
                entity.id == requestedID
            }
        )
        descriptor.fetchLimit = 1
        let payload = try PersistenceMapper.encodeAnalysis(analysis)

        if let existing = try modelContext.fetch(descriptor).first {
            guard try PersistenceMapper.decodeAnalysis(existing.payload) == analysis else {
                throw PersistenceStoreError.conflictingAnalysisID(analysis.id)
            }
            return
        }

        modelContext.insert(
            PortfolioAnalysisEntity(
                id: analysis.id,
                generatedAt: analysis.generatedAt,
                snapshotID: analysis.snapshotID,
                payload: payload
            )
        )
        try modelContext.save()
    }

    func loadAnalyses() throws -> [PortfolioAnalysis] {
        let entities = try modelContext.fetch(FetchDescriptor<PortfolioAnalysisEntity>())
        let analyses = try entities.map { try PersistenceMapper.decodeAnalysis($0.payload) }
        return analyses.sorted { lhs, rhs in
            if lhs.generatedAt != rhs.generatedAt {
                return lhs.generatedAt > rhs.generatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func loadAnalysis(id: UUID) throws -> PortfolioAnalysis? {
        let requestedID = id
        var descriptor = FetchDescriptor<PortfolioAnalysisEntity>(
            predicate: #Predicate { entity in
                entity.id == requestedID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map {
            try PersistenceMapper.decodeAnalysis($0.payload)
        }
    }
}

extension PortfolioPersistenceClient {
    static func live(modelContainer: ModelContainer) -> Self {
        let store = PersistenceStore(modelContainer: modelContainer)

        return Self(
            loadDashboardDraft: {
                try await store.loadDashboardDraft()
            },
            saveDashboardDraft: { draft in
                try await store.saveDashboardDraft(draft)
            },
            saveSnapshot: { snapshot in
                try await store.saveSnapshot(snapshot)
            },
            loadLatestSnapshot: {
                try await store.loadLatestSnapshot()
            },
            loadSnapshots: {
                try await store.loadSnapshots()
            },
            loadSnapshot: { id in
                try await store.loadSnapshot(id: id)
            },
            saveAnalysis: { analysis in
                try await store.saveAnalysis(analysis)
            },
            loadAnalyses: {
                try await store.loadAnalyses()
            },
            loadAnalysis: { id in
                try await store.loadAnalysis(id: id)
            }
        )
    }
}
