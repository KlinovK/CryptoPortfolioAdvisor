import ComposableArchitecture
import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class DashboardSubmissionTests: XCTestCase {
    func testSuccessfulSubmissionPersistsSnapshotBeforeRequestAndAnalysis() async throws {
        let snapshot = try Phase6TestFixtures.snapshot()
        let analysis = try Phase6TestFixtures.analysis()
        let events = LockIsolated<[String]>([])
        var persistence = PortfolioPersistenceClient.noop
        persistence.saveSnapshot = { saved in
            XCTAssertEqual(saved, snapshot)
            events.withValue { $0.append("snapshot") }
        }
        persistence.saveAnalysis = { saved in
            XCTAssertEqual(saved, analysis)
            events.withValue { $0.append("analysis") }
        }
        let store = makeStore(
            persistence: persistence,
            analyze: { submitted in
                XCTAssertEqual(submitted, snapshot)
                events.withValue { $0.append("request") }
                return analysis
            }
        )
        let validation = store.state.makeValidatedDraft()
        let validatedInput = try XCTUnwrap(validation.validatedInput)

        await store.send(.analyzeButtonTapped) {
            $0.validatedInput = validatedInput
            $0.snapshotPersistenceStatus = .saving
            $0.analysisSubmissionState = .submitting
            $0.pendingSnapshotForAnalysis = snapshot
        }
        await store.receive(.snapshotSaveFinished(snapshot: snapshot, result: .succeeded)) {
            $0.lastSavedSnapshot = snapshot
            $0.snapshotPersistenceStatus = .saved
        }
        await store.receive(
            .analysisRequestFinished(
                snapshotID: snapshot.id,
                result: .succeeded(analysis)
            )
        ) {
            $0.pendingAnalysisForPersistence = analysis
        }
        await store.receive(
            .analysisSaveFinished(analysisID: analysis.id, result: .succeeded)
        ) {
            $0.analysisSubmissionState = .success
            $0.pendingSnapshotForAnalysis = nil
            $0.pendingAnalysisForPersistence = nil
            $0.completedAnalysis = analysis
            $0.analysisReadinessMessage =
                "Deterministic analysis complete."
        }

        XCTAssertEqual(events.value, ["snapshot", "request", "analysis"])
    }

    func testDuplicateAnalyzeWhileSubmittingIsIgnored() async {
        var state = Phase6TestFixtures.validDashboardState()
        state.analysisSubmissionState = .submitting
        let requests = LockIsolated(0)
        let store = makeStore(
            state: state,
            analyze: { _ in
                requests.withValue { $0 += 1 }
                throw SubmissionTestError.expected
            }
        )

        await store.send(.analyzeButtonTapped)

        XCTAssertEqual(requests.value, 0)
        XCTAssertEqual(store.state.analysisSubmissionState, .submitting)
    }

    func testSnapshotSaveFailureDoesNotRequestAnalysis() async throws {
        let snapshot = try Phase6TestFixtures.snapshot()
        let requests = LockIsolated(0)
        var persistence = PortfolioPersistenceClient.noop
        persistence.saveSnapshot = { _ in throw SubmissionTestError.expected }
        let store = makeStore(
            persistence: persistence,
            analyze: { _ in
                requests.withValue { $0 += 1 }
                throw SubmissionTestError.expected
            }
        )
        let validatedInput = try XCTUnwrap(store.state.makeValidatedDraft().validatedInput)

        await store.send(.analyzeButtonTapped) {
            $0.validatedInput = validatedInput
            $0.snapshotPersistenceStatus = .saving
            $0.analysisSubmissionState = .submitting
            $0.pendingSnapshotForAnalysis = snapshot
        }
        await store.receive(.snapshotSaveFinished(snapshot: snapshot, result: .failed)) {
            let message = "Unable to save portfolio snapshot locally."
            $0.snapshotPersistenceStatus = .failed(message)
            $0.analysisSubmissionState = .failed(.snapshotPersistence(message))
        }

        XCTAssertEqual(requests.value, 0)
        XCTAssertNil(store.state.lastSavedSnapshot)
    }

    func testNetworkFailureKeepsSavedSnapshotPending() async throws {
        let snapshot = try Phase6TestFixtures.snapshot()
        let savedSnapshots = LockIsolated<[PortfolioSnapshot]>([])
        var persistence = PortfolioPersistenceClient.noop
        persistence.saveSnapshot = { saved in
            savedSnapshots.withValue { $0.append(saved) }
        }
        let store = makeStore(
            persistence: persistence,
            analyze: { _ in throw SubmissionTestError.expected }
        )
        let validatedInput = try XCTUnwrap(store.state.makeValidatedDraft().validatedInput)

        await store.send(.analyzeButtonTapped) {
            $0.validatedInput = validatedInput
            $0.snapshotPersistenceStatus = .saving
            $0.analysisSubmissionState = .submitting
            $0.pendingSnapshotForAnalysis = snapshot
        }
        await store.receive(.snapshotSaveFinished(snapshot: snapshot, result: .succeeded)) {
            $0.lastSavedSnapshot = snapshot
            $0.snapshotPersistenceStatus = .saved
        }
        await store.receive(
            .analysisRequestFinished(
                snapshotID: snapshot.id,
                result: .failed("Unable to reach the analysis service.")
            )
        ) {
            $0.analysisSubmissionState = .failed(
                .request("Unable to reach the analysis service.")
            )
        }

        XCTAssertEqual(store.state.pendingSnapshotForAnalysis?.id, snapshot.id)
        XCTAssertEqual(savedSnapshots.value.count, 1)
    }

    func testNetworkRetryReusesSnapshotWithoutSavingDuplicateAndPersistsOneAnalysis() async throws {
        let snapshot = try Phase6TestFixtures.snapshot()
        let analysis = try Phase6TestFixtures.analysis()
        let snapshotSaves = LockIsolated<[UUID]>([])
        let analysisSaves = LockIsolated<[UUID]>([])
        let requestedIDs = LockIsolated<[UUID]>([])
        let attempts = LockIsolated(0)
        var persistence = PortfolioPersistenceClient.noop
        persistence.saveSnapshot = { saved in
            snapshotSaves.withValue { $0.append(saved.id) }
        }
        persistence.saveAnalysis = { saved in
            analysisSaves.withValue { $0.append(saved.id) }
        }
        let store = makeStore(
            persistence: persistence,
            analyze: { submitted in
                requestedIDs.withValue { $0.append(submitted.id) }
                let attempt = attempts.withValue {
                    $0 += 1
                    return $0
                }
                if attempt == 1 {
                    throw SubmissionTestError.expected
                }
                return analysis
            }
        )
        let validatedInput = try XCTUnwrap(store.state.makeValidatedDraft().validatedInput)

        await store.send(.analyzeButtonTapped) {
            $0.validatedInput = validatedInput
            $0.snapshotPersistenceStatus = .saving
            $0.analysisSubmissionState = .submitting
            $0.pendingSnapshotForAnalysis = snapshot
        }
        await store.receive(.snapshotSaveFinished(snapshot: snapshot, result: .succeeded)) {
            $0.lastSavedSnapshot = snapshot
            $0.snapshotPersistenceStatus = .saved
        }
        await store.receive(
            .analysisRequestFinished(
                snapshotID: snapshot.id,
                result: .failed("Unable to reach the analysis service.")
            )
        ) {
            $0.analysisSubmissionState = .failed(
                .request("Unable to reach the analysis service.")
            )
        }
        await store.send(.retryAnalysisTapped) {
            $0.analysisSubmissionState = .submitting
        }
        await store.receive(
            .analysisRequestFinished(
                snapshotID: snapshot.id,
                result: .succeeded(analysis)
            )
        ) {
            $0.pendingAnalysisForPersistence = analysis
        }
        await store.receive(
            .analysisSaveFinished(analysisID: analysis.id, result: .succeeded)
        ) {
            $0.analysisSubmissionState = .success
            $0.pendingSnapshotForAnalysis = nil
            $0.pendingAnalysisForPersistence = nil
            $0.completedAnalysis = analysis
            $0.analysisReadinessMessage =
                "Deterministic analysis complete."
        }

        XCTAssertEqual(snapshotSaves.value, [snapshot.id])
        XCTAssertEqual(requestedIDs.value, [snapshot.id, snapshot.id])
        XCTAssertEqual(analysisSaves.value, [analysis.id])
    }

    func testAnalysisPersistenceRetryDoesNotRepeatNetworkRequest() async throws {
        let snapshot = try Phase6TestFixtures.snapshot()
        let analysis = try Phase6TestFixtures.analysis()
        let requests = LockIsolated(0)
        let saveAttempts = LockIsolated(0)
        var persistence = PortfolioPersistenceClient.noop
        persistence.saveAnalysis = { _ in
            let attempt = saveAttempts.withValue {
                $0 += 1
                return $0
            }
            if attempt == 1 {
                throw SubmissionTestError.expected
            }
        }
        let store = makeStore(
            persistence: persistence,
            analyze: { _ in
                requests.withValue { $0 += 1 }
                return analysis
            }
        )
        let validatedInput = try XCTUnwrap(store.state.makeValidatedDraft().validatedInput)

        await store.send(.analyzeButtonTapped) {
            $0.validatedInput = validatedInput
            $0.snapshotPersistenceStatus = .saving
            $0.analysisSubmissionState = .submitting
            $0.pendingSnapshotForAnalysis = snapshot
        }
        await store.receive(.snapshotSaveFinished(snapshot: snapshot, result: .succeeded)) {
            $0.lastSavedSnapshot = snapshot
            $0.snapshotPersistenceStatus = .saved
        }
        await store.receive(
            .analysisRequestFinished(
                snapshotID: snapshot.id,
                result: .succeeded(analysis)
            )
        ) {
            $0.pendingAnalysisForPersistence = analysis
        }
        await store.receive(
            .analysisSaveFinished(analysisID: analysis.id, result: .failed)
        ) {
            $0.analysisSubmissionState = .failed(
                .analysisPersistence("Unable to save completed analysis locally.")
            )
        }
        await store.send(.retryAnalysisTapped) {
            $0.analysisSubmissionState = .submitting
        }
        await store.receive(
            .analysisSaveFinished(analysisID: analysis.id, result: .succeeded)
        ) {
            $0.analysisSubmissionState = .success
            $0.pendingSnapshotForAnalysis = nil
            $0.pendingAnalysisForPersistence = nil
            $0.completedAnalysis = analysis
            $0.analysisReadinessMessage =
                "Deterministic analysis complete."
        }

        XCTAssertEqual(requests.value, 1)
        XCTAssertEqual(saveAttempts.value, 2)
    }

    func testBackendErrorMessageBecomesUserFacingRequestFailure() async throws {
        let snapshot = try Phase6TestFixtures.snapshot()
        let store = makeStore(
            analyze: { _ in
                throw PortfolioAPIClientError.server(
                    statusCode: 400,
                    code: "invalid_request",
                    message: "Duplicate portfolio symbol: LINK."
                )
            }
        )
        let validatedInput = try XCTUnwrap(store.state.makeValidatedDraft().validatedInput)

        await store.send(.analyzeButtonTapped) {
            $0.validatedInput = validatedInput
            $0.snapshotPersistenceStatus = .saving
            $0.analysisSubmissionState = .submitting
            $0.pendingSnapshotForAnalysis = snapshot
        }
        await store.receive(.snapshotSaveFinished(snapshot: snapshot, result: .succeeded)) {
            $0.lastSavedSnapshot = snapshot
            $0.snapshotPersistenceStatus = .saved
        }
        await store.receive(
            .analysisRequestFinished(
                snapshotID: snapshot.id,
                result: .failed("Duplicate portfolio symbol: LINK.")
            )
        ) {
            $0.analysisSubmissionState = .failed(
                .request("Duplicate portfolio symbol: LINK.")
            )
        }
    }

    func testMarketFailureMapsToSafeUserMessage() {
        let message = DashboardFeature.requestFailureMessage(
            for: PortfolioAPIClientError.server(
                statusCode: 503,
                code: "provider_unavailable",
                message: "provider implementation detail"
            )
        )

        XCTAssertEqual(
            message,
            "Market data is temporarily unavailable. Try again later."
        )
        XCTAssertFalse(message.contains("provider implementation detail"))
    }

    func testBackendServiceFailureMapsToSafeUserMessage() {
        let message = DashboardFeature.requestFailureMessage(
            for: PortfolioAPIClientError.server(
                statusCode: 503,
                code: "persistence_unavailable",
                message: "database implementation detail"
            )
        )

        XCTAssertEqual(message, "Analysis service is temporarily unavailable.")
        XCTAssertFalse(message.contains("database implementation detail"))
    }

    func testTransportFailureMapsToReachabilityMessage() {
        XCTAssertEqual(
            DashboardFeature.requestFailureMessage(for: PortfolioAPIClientError.transport),
            "Unable to reach the analysis service."
        )
    }

    func testTimeoutFailuresMapToRetryableMessage() {
        XCTAssertEqual(
            DashboardFeature.requestFailureMessage(for: PortfolioAPIClientError.timeout),
            "Analysis took too long. Try again."
        )
        XCTAssertEqual(
            DashboardFeature.requestFailureMessage(
                for: PortfolioAPIClientError.server(
                    statusCode: 504,
                    code: "analysis_timeout",
                    message: "internal timeout detail"
                )
            ),
            "Analysis took too long. Try again."
        )
    }

    func testAIFallbackCompletesAndRemainsClearlyIdentified() async throws {
        let snapshot = try Phase6TestFixtures.snapshot()
        let analysis = try Phase6TestFixtures.analysis(analysisMode: .aiFallback)
        let store = makeStore(analyze: { _ in analysis })
        let validatedInput = try XCTUnwrap(store.state.makeValidatedDraft().validatedInput)

        await store.send(.analyzeButtonTapped) {
            $0.validatedInput = validatedInput
            $0.snapshotPersistenceStatus = .saving
            $0.analysisSubmissionState = .submitting
            $0.pendingSnapshotForAnalysis = snapshot
        }
        await store.receive(.snapshotSaveFinished(snapshot: snapshot, result: .succeeded)) {
            $0.lastSavedSnapshot = snapshot
            $0.snapshotPersistenceStatus = .saved
        }
        await store.receive(
            .analysisRequestFinished(
                snapshotID: snapshot.id,
                result: .succeeded(analysis)
            )
        ) {
            $0.pendingAnalysisForPersistence = analysis
        }
        await store.receive(
            .analysisSaveFinished(analysisID: analysis.id, result: .succeeded)
        ) {
            $0.analysisSubmissionState = .success
            $0.pendingSnapshotForAnalysis = nil
            $0.pendingAnalysisForPersistence = nil
            $0.completedAnalysis = analysis
            $0.analysisReadinessMessage =
                "AI unavailable — deterministic analysis used."
        }

        XCTAssertEqual(store.state.completedAnalysis?.analysisMode, .aiFallback)
    }

    func testCancellationLeavesSubmissionRetryable() async throws {
        let snapshot = try Phase6TestFixtures.snapshot()
        let store = makeStore(analyze: { _ in throw CancellationError() })
        let validatedInput = try XCTUnwrap(store.state.makeValidatedDraft().validatedInput)

        await store.send(.analyzeButtonTapped) {
            $0.validatedInput = validatedInput
            $0.snapshotPersistenceStatus = .saving
            $0.analysisSubmissionState = .submitting
            $0.pendingSnapshotForAnalysis = snapshot
        }
        await store.receive(.snapshotSaveFinished(snapshot: snapshot, result: .succeeded)) {
            $0.lastSavedSnapshot = snapshot
            $0.snapshotPersistenceStatus = .saved
        }
        await store.receive(
            .analysisRequestFinished(
                snapshotID: snapshot.id,
                result: .failed("Analysis request was cancelled.")
            )
        ) {
            $0.analysisSubmissionState = .failed(
                .request("Analysis request was cancelled.")
            )
        }

        XCTAssertEqual(store.state.pendingSnapshotForAnalysis?.id, snapshot.id)
    }

    private func makeStore(
        state: DashboardFeature.State = Phase6TestFixtures.validDashboardState(),
        persistence: PortfolioPersistenceClient = .noop,
        analyze: @escaping @Sendable (PortfolioSnapshot) async throws -> PortfolioAnalysis
    ) -> TestStoreOf<DashboardFeature> {
        TestStore(initialState: state) {
            DashboardFeature()
        } withDependencies: {
            $0.date.now = Phase6TestFixtures.date
            $0.portfolioAnalysis.analyze = analyze
            $0.portfolioPersistence = persistence
            $0.uuid = .constant(Phase6TestFixtures.snapshotID)
        }
    }
}

private enum SubmissionTestError: Error, Sendable {
    case expected
}
