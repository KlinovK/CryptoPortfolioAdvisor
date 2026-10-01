import ComposableArchitecture
import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class ATAAccountMutationTests: XCTestCase {
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
        accounts: [ATAAccount]? = nil
    ) -> ATACurrentPortfolio {
        ATACurrentPortfolio(
            revision: revision, snapshotID: UUID(), confirmedAt: previous.confirmedAt,
            accounts: accounts ?? previous.accounts,
            aggregatePositions: previous.aggregatePositions,
            financialSettings: previous.financialSettings,
            corePositions: previous.corePositions, limitOrders: previous.limitOrders)
    }

    private func httpError(
        _ status: Int, _ code: String, reload: Bool? = nil
    ) -> ATAClientError {
        .http(
            ATAHTTPFailure(
                statusCode: status,
                error: ATAServiceError(code: code, message: "sanitized", reloadRequired: reload)))
    }

    func testEditorOmitsZeroAndKeepsExactDecimals() throws {
        let editor = ATAAccountEditor(
            kind: .create,
            holdings: [
                ATAHoldingDraft(
                    id: UUID(), symbol: "btc", amount: "0.12345678901234567890123456789012345678"),
                ATAHoldingDraft(id: UUID(), symbol: "SOL", amount: "0"),
            ])
        let positions = try editor.validatedPositions()
        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions[0].symbol, .btc)
        XCTAssertEqual(
            try ATADecimalCodec.encode(positions[0].amount),
            "0.12345678901234567890123456789012345678")
    }

    func testLocalizedDecimalKeyboardNormalizesOnlyEditableText() throws {
        let input = "0,12345678901234567890123456789012345678"
        let normalized = ATAEditableDecimalText.normalized(input, decimalSeparator: ",")
        XCTAssertEqual(normalized, "0.12345678901234567890123456789012345678")
        XCTAssertEqual(try ATADecimalCodec.encode(ATADecimalCodec.decode(normalized)), normalized)
        XCTAssertEqual(ATAEditableDecimalText.normalized(input, decimalSeparator: "."), input)
        XCTAssertThrowsError(try ATADecimalCodec.decode(input))
        for malformed in [
            "1,2,3", "1,2.3", "1e3", "0,1234567890123456789012345678901234567890123456789",
        ] {
            XCTAssertThrowsError(
                try ATADecimalCodec.decode(
                    ATAEditableDecimalText.normalized(malformed, decimalSeparator: ",")))
        }
    }

    func testEditorRejectsDuplicateMalformedAndNegativePositions() throws {
        let duplicate = ATAAccountEditor(
            kind: .create,
            holdings: [
                ATAHoldingDraft(id: UUID(), symbol: "BTC", amount: "1"),
                ATAHoldingDraft(id: UUID(), symbol: "btc", amount: "2"),
            ])
        XCTAssertThrowsError(try duplicate.validatedPositions()) {
            XCTAssertEqual($0 as? ATAAccountEditor.InputError, .duplicateSymbol)
        }
        for text in ["-1", "NaN", "1e3", "1,5", ""] {
            let editor = ATAAccountEditor(
                kind: .create,
                holdings: [
                    ATAHoldingDraft(id: UUID(), symbol: "BTC", amount: text)
                ])
            XCTAssertThrowsError(try editor.validatedPositions()) {
                XCTAssertEqual($0 as? ATAAccountEditor.InputError, .amount)
            }
        }
        let pathSymbol = ATAAccountEditor(
            kind: .create,
            holdings: [
                ATAHoldingDraft(id: UUID(), symbol: "../BTC", amount: "1")
            ])
        XCTAssertThrowsError(try pathSymbol.validatedPositions()) {
            XCTAssertEqual($0 as? ATAAccountEditor.InputError, .symbol)
        }
    }

    func testSameSymbolAcrossServerAccountsIsPreserved() throws {
        let current = try portfolio
        XCTAssertEqual(current.accounts.count, 2)
        XCTAssertEqual(current.accounts[0].positions[0].symbol, .btc)
        XCTAssertEqual(current.accounts[1].positions[0].symbol, .btc)
        XCTAssertEqual(current.aggregatePositions[0].symbol, .btc)
    }

    func testCreateUsesCurrentRevisionAndReplacesCompleteServerPortfolio() async throws {
        let current = try portfolio
        let serverID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        let newAccount = ATAAccount(
            id: serverID, name: "Second wallet", type: .externalWallet, positions: [])
        let returned = response(current, revision: 8, accounts: current.accounts + [newAccount])
        let requests = LockIsolated<[ATACreateAccountRequestDTO]>([])
        let reads = LockIsolated(0)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.createAccount = { body in
                requests.withValue { $0.append(body) }
                return returned
            }
            $0.ataClient.loadPortfolio = {
                reads.withValue { $0 += 1 }
                return current
            }
        }
        store.exhaustivity = .off
        await store.send(.createAccountTapped)
        await store.send(.editorNameChanged("Second wallet"))
        await store.send(.editorTypeChanged(.externalWallet))
        XCTAssertEqual(store.state.portfolio, current)  // Draft is not confirmed state.
        await store.send(.editorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
        XCTAssertEqual(requests.value.count, 1)
        XCTAssertEqual(requests.value[0].expectedRevision, 7)
        XCTAssertEqual(requests.value[0].name, "Second wallet")
        XCTAssertEqual(requests.value[0].accountType, "external_wallet")
        XCTAssertTrue(requests.value[0].positions.isEmpty)
        XCTAssertEqual(store.state.portfolio, returned)
        XCTAssertEqual(store.state.portfolio?.accounts.last?.id, serverID)
        XCTAssertNil(store.state.editor)
        XCTAssertEqual(reads.value, 0)  // No GET after a successful complete response.
    }

    func testDuplicateSubmitIsIgnoredWhileSingleMutationRuns() async throws {
        let current = try portfolio
        let returned = response(current, revision: 8)
        let gate = DeferredPortfolio()
        let writes = LockIsolated(0)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.createAccount = { _ in
                writes.withValue { $0 += 1 }
                return await gate.wait()
            }
        }
        store.exhaustivity = .off
        await store.send(.createAccountTapped)
        await store.send(.editorNameChanged("New account"))
        await store.send(.editorSubmitTapped)
        XCTAssertEqual(store.state.mutationInFlight, .create)
        await store.send(.editorSubmitTapped)
        await store.send(.deleteAccountTapped(current.accounts[1].id))
        XCTAssertEqual(store.state.portfolio, current)
        XCTAssertNil(store.state.pendingDeletion)
        await gate.resolve(returned)
        await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
        XCTAssertEqual(writes.value, 1)
    }

    func testInvalidEditorDraftNeverSubmitsOrChangesConfirmedPortfolio() async throws {
        let current = try portfolio
        let writes = LockIsolated(0)
        var initial = loaded(current)
        initial.editor = ATAAccountEditor(
            kind: .holdings(current.accounts[0].id),
            holdings: [
                ATAHoldingDraft(id: UUID(), symbol: "BTC", amount: "1"),
                ATAHoldingDraft(id: UUID(), symbol: "btc", amount: "2"),
            ])
        let store = TestStore(initialState: initial) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.updateAccountHoldings = { _, _ in
                writes.withValue { $0 += 1 }
                return current
            }
        }
        store.exhaustivity = .off
        await store.send(.editorSubmitTapped)
        XCTAssertEqual(store.state.editor?.inputError, .duplicateSymbol)
        XCTAssertEqual(store.state.portfolio, current)
        XCTAssertEqual(writes.value, 0)
    }

    func testRenameUsesAccountUUIDNotNameAndAllowsDuplicateName() async throws {
        let current = try portfolio
        let accountID = current.accounts[1].id
        let renamed = ATAAccount(
            id: accountID, name: current.accounts[0].name, type: .externalWallet,
            positions: current.accounts[1].positions)
        let returned = response(
            current, revision: 8, accounts: [current.accounts[0], renamed])
        let captured = LockIsolated<[(UUID, ATARenameAccountRequestDTO)]>([])
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.renameAccount = { id, body in
                captured.withValue { $0.append((id, body)) }
                return returned
            }
        }
        store.exhaustivity = .off
        await store.send(.renameAccountTapped(accountID))
        await store.send(.editorNameChanged(current.accounts[0].name))
        XCTAssertEqual(store.state.portfolio, current)
        await store.send(.editorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
        XCTAssertEqual(captured.value.first?.0, accountID)
        XCTAssertEqual(captured.value.first?.1.expectedRevision, 7)
        XCTAssertEqual(captured.value.first?.1.name, current.accounts[0].name)
        XCTAssertEqual(store.state.portfolio, returned)
    }

    func testCompleteHoldingsReplacementOmitsZeroAndKeepsExactAmount() async throws {
        let current = try portfolio
        let accountID = current.accounts[0].id
        let amount = "0.12345678901234567890123456789012345678"
        var initial = loaded(current)
        initial.editor = ATAAccountEditor(
            kind: .holdings(accountID),
            holdings: [
                ATAHoldingDraft(id: UUID(), symbol: "BTC", amount: amount),
                ATAHoldingDraft(id: UUID(), symbol: "ETH", amount: "0"),
                ATAHoldingDraft(id: UUID(), symbol: "USDC", amount: "2000"),
            ])
        let returned = response(current, revision: 8)
        let captured = LockIsolated<[(UUID, ATAReplaceAccountHoldingsRequestDTO)]>([])
        let store = TestStore(initialState: initial) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.updateAccountHoldings = { id, body in
                captured.withValue { $0.append((id, body)) }
                return returned
            }
        }
        store.exhaustivity = .off
        await store.send(.editorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
        XCTAssertEqual(captured.value.first?.0, accountID)
        XCTAssertEqual(captured.value.first?.1.expectedRevision, 7)
        XCTAssertEqual(captured.value.first?.1.positions.map(\.symbol), ["BTC", "USDC"])
        XCTAssertEqual(captured.value.first?.1.positions.map(\.amount), [amount, "2000"])
        XCTAssertEqual(store.state.portfolio, returned)
    }

    func testDeleteRequiresExplicitConfirmationAndUsesRevisionBody() async throws {
        let current = try portfolio
        let id = current.accounts[1].id
        let returned = response(current, revision: 8, accounts: [current.accounts[0]])
        let captured = LockIsolated<[(UUID, ATADeleteAccountRequestDTO)]>([])
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.deleteAccount = { id, body in
                captured.withValue { $0.append((id, body)) }
                return returned
            }
        }
        store.exhaustivity = .off
        await store.send(.deleteAccountConfirmed(id))
        XCTAssertTrue(captured.value.isEmpty)
        await store.send(.deleteAccountTapped(id))
        XCTAssertEqual(store.state.portfolio, current)
        await store.send(.deleteAccountConfirmed(id))
        await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
        XCTAssertEqual(captured.value.first?.0, id)
        XCTAssertEqual(captured.value.first?.1.expectedRevision, 7)
        XCTAssertEqual(store.state.portfolio?.accounts.count, 1)
    }

    func testPendingDeletionIsClearedWhenRefreshChangesRevision() async throws {
        let current = try portfolio
        let refreshed = response(current, revision: 8)
        let writes = LockIsolated(0)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.deleteAccount = { _, _ in
                writes.withValue { $0 += 1 }
                return refreshed
            }
        }
        store.exhaustivity = .off
        await store.send(.deleteAccountTapped(current.accounts[1].id))
        XCTAssertNotNil(store.state.pendingDeletion)
        await store.send(.loadFinished(generation: 0, result: .loaded(refreshed)))
        XCTAssertNil(store.state.pendingDeletion)
        await store.send(.deleteAccountConfirmed(current.accounts[1].id))
        XCTAssertEqual(writes.value, 0)
    }

    func testRevisionConflictReloadsAndKeepsDraftForExplicitReview() async throws {
        let current = try portfolio
        let refreshed = response(current, revision: 8)
        let writes = LockIsolated(0)
        let reads = LockIsolated(0)
        let gate = DeferredPortfolio()
        let conflict = httpError(409, "revision_conflict", reload: true)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.renameAccount = { _, _ in
                writes.withValue { $0 += 1 }
                throw conflict
            }
            $0.ataClient.loadPortfolio = {
                reads.withValue { $0 += 1 }
                return await gate.wait()
            }
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
        }
        store.exhaustivity = .off
        await store.send(.renameAccountTapped(current.accounts[0].id))
        await store.send(.editorNameChanged("Reviewed name"))
        await store.send(.editorSubmitTapped)
        await store.receive(
            .mutationFinished(
                generation: 1, result: .failed(.revisionConflict)))
        XCTAssertEqual(store.state.portfolio, current)
        XCTAssertTrue(store.state.reconciliationRequired)
        XCTAssertTrue(store.state.editor?.needsReview == true)
        await store.send(.editorSubmitTapped)
        XCTAssertEqual(writes.value, 1)
        await gate.resolve(refreshed)
        await store.receive(.loadFinished(generation: 2, result: .loaded(refreshed)))
        XCTAssertEqual(store.state.portfolio, refreshed)
        XCTAssertFalse(store.state.reconciliationRequired)
        XCTAssertEqual(store.state.mutationIssue, .reviewRequired)
        await store.send(.editorSubmitTapped)
        XCTAssertEqual(writes.value, 1)
        await store.send(.editorReviewAcknowledged)
        XCTAssertFalse(store.state.editor?.needsReview ?? true)
        XCTAssertEqual(reads.value, 1)
    }

    func testStateConflictAndValidationKeepConfirmedPortfolioAndDraft() async throws {
        let current = try portfolio
        for (status, code, issue) in [
            (409, "state_conflict", ATADashboardFeature.MutationIssue.stateConflict),
            (422, "validation_error", .validation),
        ] {
            let error = httpError(status, code)
            let reads = LockIsolated(0)
            let store = TestStore(initialState: loaded(current)) {
                ATADashboardFeature()
            } withDependencies: {
                $0.ataClient.renameAccount = { _, _ in throw error }
                $0.ataClient.loadPortfolio = {
                    reads.withValue { $0 += 1 }
                    return current
                }
            }
            store.exhaustivity = .off
            await store.send(.renameAccountTapped(current.accounts[0].id))
            await store.send(.editorNameChanged("Draft name"))
            await store.send(.editorSubmitTapped)
            await store.receive(.mutationFinished(generation: 1, result: .failed(issue)))
            XCTAssertEqual(store.state.portfolio, current)
            XCTAssertEqual(store.state.editor?.name, "Draft name")
            XCTAssertEqual(store.state.mutationIssue, issue)
            XCTAssertEqual(store.state.editor?.needsReview, issue == .stateConflict)
            XCTAssertEqual(reads.value, 0)
        }
    }

    func testResourceNotFoundReloadsWithoutRecreationOrReplay() async throws {
        let current = try portfolio
        let refreshed = response(current, revision: 9, accounts: [current.accounts[0]])
        let writes = LockIsolated(0)
        let missing = httpError(404, "resource_not_found")
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.renameAccount = { _, _ in
                writes.withValue { $0 += 1 }
                throw missing
            }
            $0.ataClient.loadPortfolio = { refreshed }
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
        }
        store.exhaustivity = .off
        await store.send(.renameAccountTapped(current.accounts[1].id))
        await store.send(.editorNameChanged("Still a draft"))
        await store.send(.editorSubmitTapped)
        await store.receive(
            .mutationFinished(
                generation: 1, result: .failed(.resourceNotFound)))
        await store.receive(.loadFinished(generation: 2, result: .loaded(refreshed)))
        XCTAssertEqual(writes.value, 1)
        XCTAssertEqual(store.state.portfolio, refreshed)
        XCTAssertEqual(store.state.editor?.name, "Still a draft")
        XCTAssertTrue(store.state.editor?.needsReview == true)
    }

    func testUncertainOutcomeBlocksWritesUntilReconciliation() async throws {
        let current = try portfolio
        let gate = DeferredPortfolio()
        let writes = LockIsolated(0)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.createAccount = { _ in
                writes.withValue { $0 += 1 }
                throw ATAClientError.uncertainMutationOutcome(.timeout)
            }
            $0.ataClient.loadPortfolio = { await gate.wait() }
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
        }
        store.exhaustivity = .off
        await store.send(.createAccountTapped)
        await store.send(.editorNameChanged("New account"))
        await store.send(.editorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .failed(.uncertain)))
        XCTAssertTrue(store.state.reconciliationRequired)
        XCTAssertFalse(store.state.canSubmitAccountMutation)
        await store.send(.editorSubmitTapped)
        await store.send(.deleteAccountTapped(current.accounts[1].id))
        XCTAssertEqual(writes.value, 1)
        await gate.resolve(current)
        await store.receive(.loadFinished(generation: 2, result: .loaded(current)))
        XCTAssertFalse(store.state.reconciliationRequired)
        XCTAssertTrue(store.state.canSubmitAccountMutation)
        XCTAssertTrue(store.state.editor?.needsReview == true)
        XCTAssertEqual(writes.value, 1)
    }

    func testCancelledMutationOutcomeAlsoRequiresReconciliation() async throws {
        let current = try portfolio
        let gate = DeferredPortfolio()
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.createAccount = { _ in
                throw ATAClientError.uncertainMutationOutcome(.cancelled)
            }
            $0.ataClient.loadPortfolio = { await gate.wait() }
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
        }
        store.exhaustivity = .off
        await store.send(.createAccountTapped)
        await store.send(.editorNameChanged("New account"))
        await store.send(.editorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .failed(.uncertain)))
        XCTAssertTrue(store.state.reconciliationRequired)
        XCTAssertFalse(store.state.canSubmitAccountMutation)
        await gate.resolve(current)
        await store.receive(.loadFinished(generation: 2, result: .loaded(current)))
        XCTAssertTrue(store.state.editor?.needsReview == true)
    }

    func testMutationResponseInvalidatesOlderGET() async throws {
        let current = try portfolio
        let returned = response(current, revision: 8)
        let gate = DeferredPortfolio()
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.createAccount = { _ in returned }
            $0.ataClient.loadPortfolio = { await gate.wait() }
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
        }
        store.exhaustivity = .off
        await store.send(.refreshTapped)
        let oldGeneration = store.state.requestGeneration
        await store.send(.createAccountTapped)
        await store.send(.editorNameChanged("New account"))
        await store.send(.editorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
        await store.send(.loadFinished(generation: oldGeneration, result: .loaded(current)))
        XCTAssertEqual(store.state.portfolio?.revision, 8)
        await gate.resolve(current)
    }

    func testCredentialChangeInvalidatesLateMutationResponse() async throws {
        let current = try portfolio
        let returned = response(current, revision: 8)
        let nextContext = response(current, revision: 3)
        let gate = DeferredPortfolio()
        let writes = LockIsolated(0)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.createAccount = { _ in
                writes.withValue { $0 += 1 }
                return await gate.wait()
            }
            $0.ataClient.loadPortfolio = { nextContext }
            $0.ataCredentials.save = { _ in }
            $0.ataCredentials.load = { try ATABearerToken("new-synthetic-token") }
        }
        store.exhaustivity = .off
        await store.send(.createAccountTapped)
        await store.send(.editorNameChanged("Old context draft"))
        await store.send(.editorSubmitTapped)
        await gate.waitUntilStarted()
        await store.send(.credentialSaveRequested(try ATABearerToken("new-synthetic-token")))
        XCTAssertNil(store.state.portfolio)
        XCTAssertNil(store.state.editor)
        XCTAssertTrue(store.state.reconciliationRequired)
        XCTAssertFalse(store.state.canSubmitPortfolioMutation)
        XCTAssertEqual(writes.value, 1)
        // The mock continuation does not cooperate with cancellation; release it so
        // the cancelled effect can finish before the replacement credential loads.
        await gate.resolve(returned)
        await store.receive(.credentialSaved(generation: 2, succeeded: true))
        await store.receive(.loadFinished(generation: 3, result: .loaded(nextContext)))
        await store.send(.mutationFinished(generation: 1, result: .succeeded(returned)))
        XCTAssertEqual(store.state.portfolio, nextContext)
        XCTAssertEqual(writes.value, 1)
    }
}

private actor DeferredPortfolio {
    private var value: ATACurrentPortfolio?
    private var waiter: CheckedContinuation<ATACurrentPortfolio, Never>?
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?

    func wait() async -> ATACurrentPortfolio {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        if let value { return value }
        return await withCheckedContinuation { waiter = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
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
