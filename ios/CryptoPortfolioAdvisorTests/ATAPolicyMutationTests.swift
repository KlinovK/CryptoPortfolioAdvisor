import ComposableArchitecture
import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class ATAPolicyMutationTests: XCTestCase {
    private var portfolio: ATACurrentPortfolio {
        get throws {
            let dto = try JSONDecoder().decode(
                ATACurrentPortfolioDTO.self, from: Data(ATAFoundationFixtures.portfolio.utf8))
            return try ATAResponseMapper.domain(from: dto)
        }
    }

    private func loaded(_ portfolio: ATACurrentPortfolio) -> ATADashboardFeature.State {
        var state = ATADashboardFeature.State(configurationAvailable: true)
        state.hasAppeared = true
        state.portfolio = portfolio
        state.loadState = .loaded
        return state
    }

    private func response(
        _ previous: ATACurrentPortfolio, revision: Int,
        settings: ATAFinancialSettings? = nil, cores: [ATACorePosition]? = nil
    ) -> ATACurrentPortfolio {
        ATACurrentPortfolio(
            revision: revision, snapshotID: UUID(), confirmedAt: previous.confirmedAt,
            accounts: previous.accounts, aggregatePositions: previous.aggregatePositions,
            financialSettings: settings ?? previous.financialSettings,
            corePositions: cores ?? previous.corePositions, limitOrders: previous.limitOrders)
    }

    private func httpError(
        _ status: Int, _ code: String, reload: Bool? = nil
    ) -> ATAClientError {
        .http(
            ATAHTTPFailure(
                statusCode: status,
                error: ATAServiceError(code: code, message: "sanitized", reloadRequired: reload)))
    }

    func testEditorsStartFromExactServerValuesAndCoreVersion() async throws {
        let current = try portfolio
        let store = TestStore(initialState: loaded(current)) { ATADashboardFeature() }
        store.exhaustivity = .off
        await store.send(.editFinancialSettingsTapped)
        XCTAssertEqual(store.state.policyEditor?.firstValue, "250")
        XCTAssertEqual(store.state.policyEditor?.secondValue, "12")
        await store.send(.policyEditorCancelled)
        await store.send(.editCorePositionTapped(.eth))
        XCTAssertEqual(store.state.policyEditor?.kind, .corePosition(.eth))
        XCTAssertEqual(store.state.policyEditor?.firstValue, "2")
        XCTAssertEqual(store.state.policyEditor?.secondValue, "2.5")
        XCTAssertEqual(store.state.policyEditor?.policyVersion, 1)
    }

    func testSharedMutationMessagesDoNotMislabelPolicyFailuresAsAccountFailures() {
        for issue in [
            ATADashboardFeature.MutationIssue.validation, .resourceNotFound, .service,
            .authentication,
        ] {
            XCTAssertFalse(issue.message.lowercased().contains("account"))
        }
    }

    func testFinancialInputAcceptsExactFractionalRunwayAndRejectsInvalidValues() throws {
        var editor = try ATAPolicyEditor(
            financialSettings: ATAFinancialSettings(
                monthlyExpensesUSD: Decimal(250), targetExpenseRunwayMonths: Decimal(12)))
        editor.firstValue = "200.123456789123456789"
        editor.secondValue = "12.500000000000000001"
        let values = try editor.financialValues()
        XCTAssertEqual(
            try ATADecimalCodec.encode(values.monthlyExpensesUSD), "200.123456789123456789")
        XCTAssertEqual(
            try ATADecimalCodec.encode(values.targetRunwayMonths), "12.500000000000000001")
        for text in ["0", "-1", "1e2", "1,5", "NaN", ""] {
            editor.firstValue = text
            XCTAssertThrowsError(try editor.financialValues()) {
                XCTAssertEqual($0 as? ATAPolicyEditor.InputError, .monthlyExpenses)
            }
            editor.firstValue = "250"
            editor.secondValue = text
            XCTAssertThrowsError(try editor.financialValues()) {
                XCTAssertEqual($0 as? ATAPolicyEditor.InputError, .targetRunway)
            }
        }
    }

    func testFinancialSubmissionUsesCurrentRevisionAndCompleteResponseWithoutGET() async throws {
        let current = try portfolio
        let updatedSettings = ATAFinancialSettings(
            monthlyExpensesUSD: try ATADecimalCodec.decode("200.123456789123456789"),
            targetExpenseRunwayMonths: try ATADecimalCodec.decode("12.500000000000000001"))
        let returned = response(current, revision: 8, settings: updatedSettings)
        let requests = LockIsolated<[ATAUpdateFinancialSettingsRequestDTO]>([])
        let reads = LockIsolated(0)
        let gate = PolicyGate()
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.updateFinancialSettings = { request in
                requests.withValue { $0.append(request) }
                return await gate.wait()
            }
            $0.ataClient.loadPortfolio = {
                reads.withValue { $0 += 1 }
                return current
            }
        }
        store.exhaustivity = .off
        await store.send(.editFinancialSettingsTapped)
        await store.send(.policyFirstValueChanged("200.123456789123456789"))
        await store.send(.policySecondValueChanged("12.500000000000000001"))
        XCTAssertEqual(store.state.portfolio, current)
        await store.send(.policyEditorSubmitTapped)
        XCTAssertEqual(store.state.mutationInFlight, .financialSettings)
        await store.send(.policyEditorSubmitTapped)
        await store.send(.createAccountTapped)
        XCTAssertNil(store.state.editor)
        XCTAssertEqual(store.state.portfolio, current)
        await gate.resolve(returned)
        await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
        XCTAssertEqual(requests.value.count, 1)
        XCTAssertEqual(requests.value[0].expectedRevision, 7)
        XCTAssertEqual(requests.value[0].monthlyExpensesUSD, "200.123456789123456789")
        XCTAssertEqual(requests.value[0].targetExpenseRunwayMonths, "12.500000000000000001")
        XCTAssertEqual(store.state.portfolio, returned)
        XCTAssertNil(store.state.policyEditor)
        XCTAssertEqual(reads.value, 0)
    }

    func testInvalidFinancialInputAndUnchangedSettingsDoNotSend() async throws {
        let current = try portfolio
        let writes = LockIsolated(0)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.updateFinancialSettings = { _ in
                writes.withValue { $0 += 1 }
                return current
            }
        }
        store.exhaustivity = .off
        await store.send(.editFinancialSettingsTapped)
        await store.send(.policyEditorSubmitTapped)
        XCTAssertEqual(store.state.policyEditor?.inputError, .unchanged)
        await store.send(.policyFirstValueChanged("0"))
        await store.send(.policyEditorSubmitTapped)
        XCTAssertEqual(store.state.policyEditor?.inputError, .monthlyExpenses)
        await store.send(.policyFirstValueChanged("251"))
        await store.send(.policySecondValueChanged("12.5e0"))
        await store.send(.policyEditorSubmitTapped)
        XCTAssertEqual(store.state.policyEditor?.inputError, .targetRunway)
        XCTAssertEqual(writes.value, 0)
        XCTAssertEqual(store.state.portfolio, current)
    }

    func testCoreConstraintsAndUnsupportedAssetVersion() throws {
        let core = ATACorePosition(
            symbol: .eth, hardFloor: Decimal(2), preferredQuantity: Decimal(2.5),
            policyVersion: 1)
        var editor = try ATAPolicyEditor(corePosition: core)
        editor.firstValue = "0"
        XCTAssertThrowsError(try editor.coreValues(aggregateAmount: Decimal(3))) {
            XCTAssertEqual($0 as? ATAPolicyEditor.InputError, .hardFloor)
        }
        editor.firstValue = "2.5"
        editor.secondValue = "0"
        XCTAssertThrowsError(try editor.coreValues(aggregateAmount: Decimal(3))) {
            XCTAssertEqual($0 as? ATAPolicyEditor.InputError, .preferredQuantity)
        }
        editor.secondValue = "2.4"
        XCTAssertThrowsError(try editor.coreValues(aggregateAmount: Decimal(3))) {
            XCTAssertEqual($0 as? ATAPolicyEditor.InputError, .preferredBelowFloor)
        }
        editor.secondValue = "3"
        XCTAssertThrowsError(try editor.coreValues(aggregateAmount: Decimal(2))) {
            XCTAssertEqual($0 as? ATAPolicyEditor.InputError, .floorExceedsHoldings)
        }
        let unsupported = try ATAPolicyEditor(
            corePosition: ATACorePosition(
                symbol: try AssetSymbol("XRP"), hardFloor: Decimal(1),
                preferredQuantity: Decimal(2), policyVersion: 1))
        XCTAssertThrowsError(try unsupported.coreValues(aggregateAmount: Decimal(3))) {
            XCTAssertEqual($0 as? ATAPolicyEditor.InputError, .unsupportedCorePolicy)
        }
        let future = try ATAPolicyEditor(
            corePosition: ATACorePosition(
                symbol: .eth, hardFloor: Decimal(1), preferredQuantity: Decimal(2),
                policyVersion: 2))
        XCTAssertThrowsError(try future.coreValues(aggregateAmount: Decimal(3))) {
            XCTAssertEqual($0 as? ATAPolicyEditor.InputError, .unsupportedCorePolicy)
        }
    }

    func testCoreSubmissionUsesSymbolRevisionExactValuesAndWholeResponse() async throws {
        let current = try portfolio
        let otherCore = ATACorePosition(
            symbol: .btc, hardFloor: Decimal(string: "0.1")!,
            preferredQuantity: Decimal(string: "0.2")!, policyVersion: 1)
        let withOtherCore = response(
            current, revision: current.revision, cores: [otherCore] + current.corePositions)
        let core = ATACorePosition(
            symbol: .eth, hardFloor: try ATADecimalCodec.decode("2.000000000000000001"),
            preferredQuantity: try ATADecimalCodec.decode("2.500000000000000001"),
            policyVersion: 1)
        let returned = response(withOtherCore, revision: 8, cores: [otherCore, core])
        let captured = LockIsolated<[(AssetSymbol, ATAUpdateCorePositionRequestDTO)]>([])
        let store = TestStore(initialState: loaded(withOtherCore)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.updateCorePosition = { symbol, body in
                captured.withValue { $0.append((symbol, body)) }
                return returned
            }
        }
        store.exhaustivity = .off
        await store.send(.editCorePositionTapped(.eth))
        await store.send(.policyFirstValueChanged("2.000000000000000001"))
        await store.send(.policySecondValueChanged("2.500000000000000001"))
        XCTAssertEqual(store.state.portfolio, withOtherCore)
        await store.send(.policyEditorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
        XCTAssertEqual(captured.value.first?.0, .eth)
        XCTAssertEqual(captured.value.first?.1.expectedRevision, 7)
        XCTAssertEqual(captured.value.first?.1.hardFloor, "2.000000000000000001")
        XCTAssertEqual(captured.value.first?.1.preferredQuantity, "2.500000000000000001")
        XCTAssertEqual(store.state.portfolio, returned)
        XCTAssertEqual(store.state.portfolio?.corePositions.first, otherCore)
        XCTAssertEqual(store.state.portfolio?.accounts, withOtherCore.accounts)
        XCTAssertEqual(store.state.portfolio?.limitOrders, withOtherCore.limitOrders)
    }

    func testSemanticallyUnchangedCorePolicyCannotSubmit() async throws {
        let current = try portfolio
        let writes = LockIsolated(0)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.updateCorePosition = { _, _ in
                writes.withValue { $0 += 1 }
                return current
            }
        }
        store.exhaustivity = .off
        await store.send(.editCorePositionTapped(.eth))
        await store.send(.policyFirstValueChanged("2.00"))
        await store.send(.policySecondValueChanged("2.500"))
        await store.send(.policyEditorSubmitTapped)
        XCTAssertEqual(store.state.policyEditor?.inputError, .unchanged)
        XCTAssertEqual(writes.value, 0)
        XCTAssertEqual(store.state.portfolio, current)
    }

    func testAccountMutationBlocksPolicyMutationGlobally() async throws {
        let current = try portfolio
        let returned = response(current, revision: 8)
        let gate = PolicyGate()
        let policyWrites = LockIsolated(0)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.createAccount = { _ in await gate.wait() }
            $0.ataClient.updateFinancialSettings = { _ in
                policyWrites.withValue { $0 += 1 }
                return current
            }
        }
        store.exhaustivity = .off
        await store.send(.createAccountTapped)
        await store.send(.editorNameChanged("New"))
        await store.send(.editorSubmitTapped)
        await store.send(.editFinancialSettingsTapped)
        XCTAssertNil(store.state.policyEditor)
        XCTAssertEqual(policyWrites.value, 0)
        await gate.resolve(returned)
        await store.receive(
            .mutationFinished(
                generation: 1, result: .succeeded(returned)))
    }

    func testRevisionConflictReloadsPolicyDraftWithoutReplay() async throws {
        let current = try portfolio
        let refreshed = response(current, revision: 8)
        let gate = PolicyGate()
        let writes = LockIsolated(0)
        let conflict = httpError(409, "revision_conflict", reload: true)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.updateFinancialSettings = { _ in
                writes.withValue { $0 += 1 }
                throw conflict
            }
            $0.ataClient.loadPortfolio = { await gate.wait() }
            $0.ataCredentials.load = { try ATABearerToken("synthetic-token") }
        }
        store.exhaustivity = .off
        await store.send(.editFinancialSettingsTapped)
        await store.send(.policyFirstValueChanged("300"))
        await store.send(.policyEditorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .failed(.revisionConflict)))
        XCTAssertTrue(store.state.reconciliationRequired)
        XCTAssertTrue(store.state.policyEditor?.needsReview == true)
        XCTAssertEqual(store.state.portfolio, current)
        await store.send(.policyEditorSubmitTapped)
        XCTAssertEqual(writes.value, 1)
        await gate.resolve(refreshed)
        await store.receive(.loadFinished(generation: 2, result: .loaded(refreshed)))
        XCTAssertEqual(store.state.portfolio, refreshed)
        XCTAssertTrue(store.state.policyEditor?.needsReview == true)
        await store.send(.editorReviewAcknowledged)
        XCTAssertFalse(store.state.policyEditor?.needsReview ?? true)
        XCTAssertEqual(writes.value, 1)
    }

    func testStateConflictAndValidationPreservePolicyDraftWithoutReplay() async throws {
        let current = try portfolio
        for (status, code, issue) in [
            (409, "state_conflict", ATADashboardFeature.MutationIssue.stateConflict),
            (422, "validation_error", .validation),
        ] {
            let error = httpError(status, code)
            let writes = LockIsolated(0)
            let reads = LockIsolated(0)
            let store = TestStore(initialState: loaded(current)) {
                ATADashboardFeature()
            } withDependencies: {
                $0.ataClient.updateFinancialSettings = { _ in
                    writes.withValue { $0 += 1 }
                    throw error
                }
                $0.ataClient.loadPortfolio = {
                    reads.withValue { $0 += 1 }
                    return current
                }
            }
            store.exhaustivity = .off
            await store.send(.editFinancialSettingsTapped)
            await store.send(.policyFirstValueChanged("300"))
            await store.send(.policyEditorSubmitTapped)
            await store.receive(.mutationFinished(generation: 1, result: .failed(issue)))
            XCTAssertEqual(store.state.portfolio, current)
            XCTAssertEqual(store.state.policyEditor?.firstValue, "300")
            XCTAssertEqual(store.state.policyEditor?.needsReview, issue == .stateConflict)
            XCTAssertEqual(reads.value, 0)
            XCTAssertEqual(writes.value, 1)
        }
    }

    func testMissingCorePolicyRefreshesWithoutReplaying() async throws {
        let current = try portfolio
        let refreshed = response(current, revision: 8, cores: [])
        let writes = LockIsolated(0)
        let missing = httpError(404, "resource_not_found")
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.updateCorePosition = { _, _ in
                writes.withValue { $0 += 1 }
                throw missing
            }
            $0.ataClient.loadPortfolio = { refreshed }
            $0.ataCredentials.load = { try ATABearerToken("synthetic-token") }
        }
        store.exhaustivity = .off
        await store.send(.editCorePositionTapped(.eth))
        await store.send(.policyFirstValueChanged("2.1"))
        await store.send(.policyEditorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .failed(.resourceNotFound)))
        await store.receive(.loadFinished(generation: 2, result: .loaded(refreshed)))
        XCTAssertEqual(store.state.portfolio, refreshed)
        XCTAssertTrue(store.state.policyEditor?.needsReview == true)
        await store.send(.editorReviewAcknowledged)
        await store.send(.policyEditorSubmitTapped)
        XCTAssertEqual(store.state.policyEditor?.inputError, .policyMissing)
        XCTAssertEqual(writes.value, 1)
    }

    func testUncertainOutcomeBlocksAllWritesUntilReconciliation() async throws {
        let current = try portfolio
        let gate = PolicyGate()
        let writes = LockIsolated(0)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.updateFinancialSettings = { _ in
                writes.withValue { $0 += 1 }
                throw ATAClientError.uncertainMutationOutcome(.timeout)
            }
            $0.ataClient.loadPortfolio = { await gate.wait() }
            $0.ataCredentials.load = { try ATABearerToken("synthetic-token") }
        }
        store.exhaustivity = .off
        await store.send(.editFinancialSettingsTapped)
        await store.send(.policyFirstValueChanged("300"))
        await store.send(.policyEditorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .failed(.uncertain)))
        XCTAssertFalse(store.state.canSubmitPortfolioMutation)
        await store.send(.createAccountTapped)
        await store.send(.policyEditorSubmitTapped)
        XCTAssertNil(store.state.editor)
        XCTAssertEqual(writes.value, 1)
        await gate.resolve(current)
        await store.receive(.loadFinished(generation: 2, result: .loaded(current)))
        XCTAssertTrue(store.state.canSubmitPortfolioMutation)
        XCTAssertTrue(store.state.policyEditor?.needsReview == true)
        XCTAssertEqual(writes.value, 1)
    }

    func testCancelledPolicyOutcomeAlsoRequiresReconciliation() async throws {
        let current = try portfolio
        let gate = PolicyGate()
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.updateFinancialSettings = { _ in
                throw ATAClientError.uncertainMutationOutcome(.cancelled)
            }
            $0.ataClient.loadPortfolio = { await gate.wait() }
            $0.ataCredentials.load = { try ATABearerToken("synthetic-token") }
        }
        store.exhaustivity = .off
        await store.send(.editFinancialSettingsTapped)
        await store.send(.policyFirstValueChanged("300"))
        await store.send(.policyEditorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .failed(.uncertain)))
        XCTAssertFalse(store.state.canSubmitPortfolioMutation)
        await gate.resolve(current)
        await store.receive(.loadFinished(generation: 2, result: .loaded(current)))
        XCTAssertTrue(store.state.policyEditor?.needsReview == true)
    }

    func testOlderGETCannotOverwritePolicyMutationResponse() async throws {
        let current = try portfolio
        let returned = response(
            current, revision: 8,
            settings: ATAFinancialSettings(
                monthlyExpensesUSD: Decimal(300), targetExpenseRunwayMonths: Decimal(12)))
        let gate = PolicyGate()
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.updateFinancialSettings = { _ in returned }
            $0.ataClient.loadPortfolio = { await gate.wait() }
            $0.ataCredentials.load = { try ATABearerToken("synthetic-token") }
        }
        store.exhaustivity = .off
        await store.send(.refreshTapped)
        let oldGeneration = store.state.requestGeneration
        await store.send(.editFinancialSettingsTapped)
        await store.send(.policyFirstValueChanged("300"))
        await store.send(.policyEditorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
        await store.send(.loadFinished(generation: oldGeneration, result: .loaded(current)))
        XCTAssertEqual(store.state.portfolio, returned)
        await gate.resolve(current)
    }

    func testCredentialReplacementInvalidatesOldPolicyResponseAndDraft() async throws {
        let current = try portfolio
        let returned = response(current, revision: 8)
        let nextContext = response(current, revision: 3)
        let gate = PolicyGate()
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.updateFinancialSettings = { _ in await gate.wait() }
            $0.ataClient.loadPortfolio = { nextContext }
            $0.ataCredentials.save = { _ in }
            $0.ataCredentials.load = { try ATABearerToken("new-synthetic-token") }
        }
        store.exhaustivity = .off
        await store.send(.editFinancialSettingsTapped)
        await store.send(.policyFirstValueChanged("300"))
        await store.send(.policyEditorSubmitTapped)
        await store.send(.credentialSaveRequested(try ATABearerToken("new-synthetic-token")))
        XCTAssertNil(store.state.portfolio)
        XCTAssertNil(store.state.policyEditor)
        await store.receive(.credentialSaved(generation: 2, succeeded: true))
        await store.receive(.loadFinished(generation: 3, result: .loaded(nextContext)))
        await store.send(.mutationFinished(generation: 1, result: .succeeded(returned)))
        XCTAssertEqual(store.state.portfolio, nextContext)
        await gate.resolve(returned)
    }
}

private actor PolicyGate {
    private var value: ATACurrentPortfolio?
    private var waiter: CheckedContinuation<ATACurrentPortfolio, Never>?

    func wait() async -> ATACurrentPortfolio {
        if let value { return value }
        return await withCheckedContinuation { waiter = $0 }
    }

    func resolve(_ portfolio: ATACurrentPortfolio) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: portfolio)
        } else {
            value = portfolio
        }
    }
}
