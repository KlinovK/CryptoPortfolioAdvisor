import ComposableArchitecture
import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class ATAOrderMutationTests: XCTestCase {
    private var portfolio: ATACurrentPortfolio {
        get throws {
            let dto = try JSONDecoder().decode(
                ATACurrentPortfolioDTO.self, from: Data(ATAFoundationFixtures.portfolio.utf8))
            return try ATAResponseMapper.domain(from: dto)
        }
    }

    private func loaded(_ value: ATACurrentPortfolio) -> ATADashboardFeature.State {
        var state = ATADashboardFeature.State(configurationAvailable: true)
        state.hasAppeared = true
        state.portfolio = value
        state.loadState = .loaded
        return state
    }

    private func response(
        _ current: ATACurrentPortfolio, revision: Int,
        orders: [ATALimitOrder]? = nil
    ) -> ATACurrentPortfolio {
        ATACurrentPortfolio(
            revision: revision, snapshotID: UUID(), confirmedAt: current.confirmedAt,
            accounts: current.accounts, aggregatePositions: current.aggregatePositions,
            financialSettings: current.financialSettings, corePositions: current.corePositions,
            limitOrders: orders ?? current.limitOrders)
    }

    private func error(_ status: Int, _ code: String, reload: Bool? = nil) -> ATAClientError {
        .http(
            ATAHTTPFailure(
                statusCode: status,
                error: ATAServiceError(code: code, message: "safe", reloadRequired: reload)))
    }

    func testCreateUsesAccountUUIDExactDecimalsAndCompleteServerResponse() async throws {
        let current = try portfolio
        let returned = response(current, revision: 8)
        let requests = LockIsolated<[ATACreateOrderRequestDTO]>([])
        let reads = LockIsolated(0)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.createLimitOrder = { body in
                requests.withValue { $0.append(body) }
                return returned
            }
            $0.ataClient.loadPortfolio = {
                reads.withValue { $0 += 1 }
                return current
            }
        }
        store.exhaustivity = .off
        await store.send(.createLimitOrderTapped)
        await store.send(.orderAccountChanged(current.accounts[1].id))
        await store.send(.orderAssetChanged(.sol))
        await store.send(.orderSideChanged(.sell))
        await store.send(.orderTargetPriceChanged("97.123456789012345678"))
        await store.send(.orderQuantityChanged("0.001234567890123456"))
        XCTAssertEqual(store.state.portfolio, current)
        await store.send(.orderEditorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
        XCTAssertEqual(requests.value.count, 1)
        XCTAssertEqual(requests.value[0].accountID, current.accounts[1].id.uuidString.lowercased())
        XCTAssertEqual(requests.value[0].expectedRevision, 7)
        XCTAssertEqual(requests.value[0].asset, "SOL")
        XCTAssertEqual(requests.value[0].side, "sell")
        XCTAssertEqual(requests.value[0].targetPrice, "97.123456789012345678")
        XCTAssertEqual(requests.value[0].quantityAsset, "0.001234567890123456")
        XCTAssertEqual(store.state.portfolio, returned)
        XCTAssertNil(store.state.orderEditor)
        XCTAssertEqual(reads.value, 0)
    }

    func testCreateValidationRejectsZeroNegativeMalformedAndMissingAccount() throws {
        let current = try portfolio
        var editor = ATAOrderEditor(kind: .create, accountID: current.accounts[0].id)
        editor.targetPrice = "10"
        editor.quantityAsset = "0.5"
        XCTAssertNoThrow(try editor.validatedCreateRequest(portfolio: current))
        for bad in ["", "0", "-1", "1,2", "1e2", "NaN"] {
            editor.targetPrice = bad
            XCTAssertThrowsError(try editor.validatedCreateRequest(portfolio: current)) {
                XCTAssertEqual($0 as? ATAOrderEditor.InputError, .targetPrice)
            }
            editor.targetPrice = "10"
            editor.quantityAsset = bad
            XCTAssertThrowsError(try editor.validatedCreateRequest(portfolio: current)) {
                XCTAssertEqual($0 as? ATAOrderEditor.InputError, .quantity)
            }
            editor.quantityAsset = "0.5"
        }

        editor.accountID = UUID()
        XCTAssertThrowsError(try editor.validatedCreateRequest(portfolio: current)) {
            XCTAssertEqual($0 as? ATAOrderEditor.InputError, .accountMissing)
        }
        editor.accountID = current.accounts[0].id
        editor.asset = try AssetSymbol("XRP")
        XCTAssertThrowsError(try editor.validatedCreateRequest(portfolio: current)) {
            XCTAssertEqual($0 as? ATAOrderEditor.InputError, .unsupportedAsset)
        }
    }

    func testDuplicateAccountNamesStillSelectStableAccountIdentity() throws {
        let current = try portfolio
        let duplicated = ATAAccount(
            id: current.accounts[1].id, name: current.accounts[0].name,
            type: current.accounts[1].type, positions: current.accounts[1].positions)
        let sameNames = ATACurrentPortfolio(
            revision: current.revision, snapshotID: current.snapshotID,
            confirmedAt: current.confirmedAt,
            accounts: [current.accounts[0], duplicated],
            aggregatePositions: current.aggregatePositions,
            financialSettings: current.financialSettings,
            corePositions: current.corePositions, limitOrders: current.limitOrders)
        let editor = ATAOrderEditor(
            kind: .create, accountID: duplicated.id, targetPrice: "97", quantityAsset: "1")
        let request = try editor.validatedCreateRequest(portfolio: sameNames)
        XCTAssertEqual(request.accountID, duplicated.id.uuidString.lowercased())
        XCTAssertNotEqual(request.accountID, current.accounts[0].id.uuidString.lowercased())
    }

    func testFillStartsFromOwningAccountAndRequiresExplicitSettlement() async throws {
        let current = try portfolio
        let order = current.limitOrders[0]
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off
        await store.send(.confirmExternalFillTapped(order.id))
        let editor = try XCTUnwrap(store.state.orderEditor)
        XCTAssertEqual(editor.accountID, order.accountID)
        XCTAssertEqual(editor.holdings.map(\.symbol), ["BTC", "ETH", "USDC"])
        XCTAssertEqual(editor.holdings.map(\.amount).last, "2000")
        XCTAssertNil(editor.settlementAsset)
        XCTAssertThrowsError(try editor.validatedFillRequest(portfolio: current)) {
            XCTAssertEqual($0 as? ATAOrderEditor.InputError, .settlementAsset)
        }
        var invalid = editor
        invalid.settlementAsset = .btc
        XCTAssertThrowsError(try invalid.validatedFillRequest(portfolio: current)) {
            XCTAssertEqual($0 as? ATAOrderEditor.InputError, .settlementAsset)
        }
        await store.send(.orderEditorCancelled)
        await store.send(.confirmExternalFillTapped(current.limitOrders[1].id))
        XCTAssertNil(store.state.orderEditor)
    }

    func testFillSubmitsCompleteExactPostFillHoldingsWithoutInferredTerms() async throws {
        let current = try portfolio
        let returned = response(current, revision: 8)
        let captured = LockIsolated<[(UUID, ATAConfirmOrderFilledRequestDTO)]>([])
        let reads = LockIsolated(0)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.ataClient.confirmLimitOrderFilled = { id, body in
                captured.withValue { $0.append((id, body)) }
                return returned
            }
            $0.ataClient.loadPortfolio = {
                reads.withValue { $0 += 1 }
                return current
            }
        }
        store.exhaustivity = .off
        await store.send(.confirmExternalFillTapped(current.limitOrders[0].id))
        let rows = try XCTUnwrap(store.state.orderEditor?.holdings)
        await store.send(.orderSettlementChanged(.usdc))
        await store.send(
            .orderHoldingAmountChanged(rows[0].id, "0.13345678901234567890123456789012345678"))
        await store.send(.orderHoldingAmountChanged(rows[2].id, "1500.123456789012345678"))
        await store.send(.orderEditorSubmitTapped)
        XCTAssertEqual(store.state.portfolio, current)
        await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
        XCTAssertEqual(captured.value.count, 1)
        XCTAssertEqual(captured.value[0].0, current.limitOrders[0].id)
        let body = captured.value[0].1
        XCTAssertEqual(body.expectedRevision, 7)
        XCTAssertEqual(body.settlementAsset, "USDC")
        XCTAssertEqual(body.positions.map(\.symbol), ["BTC", "ETH", "USDC"])
        XCTAssertEqual(body.positions[0].amount, "0.13345678901234567890123456789012345678")
        XCTAssertEqual(body.positions[1].amount, "3.4503")
        XCTAssertEqual(body.positions[2].amount, "1500.123456789012345678")
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["expected_revision", "settlement_asset", "positions"])
        XCTAssertEqual(reads.value, 0)
        XCTAssertEqual(store.state.portfolio, returned)
    }

    func testFillHoldingsValidationOmitsZeroRejectsDuplicatesAndNegative() throws {
        let current = try portfolio
        let id = current.limitOrders[0].id
        var editor = ATAOrderEditor(
            kind: .externalFill(id), accountID: current.accounts[0].id,
            settlementAsset: .usdt,
            holdings: [
                ATAHoldingDraft(id: UUID(), symbol: "BTC", amount: "0.2"),
                ATAHoldingDraft(id: UUID(), symbol: "USDT", amount: "0"),
            ])
        XCTAssertEqual(
            try editor.validatedFillRequest(portfolio: current).positions.map(\.symbol), ["BTC"])
        editor.holdings[1].symbol = "btc"
        editor.holdings[1].amount = "2"
        XCTAssertThrowsError(try editor.validatedFillRequest(portfolio: current)) {
            XCTAssertEqual($0 as? ATAOrderEditor.InputError, .holdings(.duplicateSymbol))
        }
        for bad in ["-1", "1e2", "1,5", ""] {
            editor.holdings[1].symbol = "USDT"
            editor.holdings[1].amount = bad
            XCTAssertThrowsError(try editor.validatedFillRequest(portfolio: current)) {
                XCTAssertEqual($0 as? ATAOrderEditor.InputError, .holdings(.amount))
            }
        }
    }

    func testCancelAndExpireUseSeparateEndpointsCurrentRevisionAndNoOptimism() async throws {
        for operation in [ATAOrderLifecycleDraft.Operation.cancel, .expire] {
            let current = try portfolio
            let returned = response(current, revision: 8)
            let captured = LockIsolated<[(UUID, Int)]>([])
            let store = TestStore(initialState: loaded(current)) {
                ATADashboardFeature()
            } withDependencies: {
                $0.ataClient.cancelLimitOrder = { id, body in
                    if operation == .cancel {
                        captured.withValue { $0.append((id, body.expectedRevision)) }
                    }
                    return returned
                }
                $0.ataClient.expireLimitOrder = { id, body in
                    if operation == .expire {
                        captured.withValue { $0.append((id, body.expectedRevision)) }
                    }
                    return returned
                }
            }
            store.exhaustivity = .off
            await store.send(.orderLifecycleTapped(current.limitOrders[1].id, operation))
            XCTAssertNil(store.state.orderLifecycle)
            await store.send(.orderLifecycleTapped(current.limitOrders[0].id, operation))
            await store.send(.orderLifecycleConfirmed)
            XCTAssertEqual(store.state.portfolio, current)
            await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
            XCTAssertEqual(captured.value.count, 1)
            XCTAssertEqual(captured.value[0].0, current.limitOrders[0].id)
            XCTAssertEqual(captured.value[0].1, 7)
            XCTAssertEqual(store.state.portfolio, returned)
        }
    }

    func testConflictsReconcileWithoutReplayAndPreserveFillDraft() async throws {
        for (status, code, reload) in [
            (409, "revision_conflict", true), (404, "resource_not_found", false),
            (0, "transport", false),
        ] {
            let current = try portfolio
            let refreshed = response(current, revision: 8)
            let writes = LockIsolated(0)
            let gate = OrderGate()
            let failure: ATAClientError =
                status == 0
                ? .uncertainMutationOutcome(.connection)
                : error(status, code, reload: reload)
            let store = TestStore(initialState: loaded(current)) {
                ATADashboardFeature()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.ataClient.confirmLimitOrderFilled = { _, _ in
                    writes.withValue { $0 += 1 }
                    throw failure
                }
                $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
                $0.ataClient.loadPortfolio = { await gate.wait() }
            }
            store.exhaustivity = .off
            await store.send(.confirmExternalFillTapped(current.limitOrders[0].id))
            await store.send(.orderSettlementChanged(.usdc))
            await store.send(.orderEditorSubmitTapped)
            let issue: ATADashboardFeature.MutationIssue =
                status == 0 ? .uncertain : (status == 404 ? .resourceNotFound : .revisionConflict)
            await store.receive(.mutationFinished(generation: 1, result: .failed(issue)))
            XCTAssertTrue(store.state.reconciliationRequired)
            await store.send(.createAccountTapped)
            XCTAssertNil(store.state.editor)
            await gate.resolve(refreshed)
            await store.receive(.loadFinished(generation: 2, result: .loaded(refreshed)))
            XCTAssertFalse(store.state.reconciliationRequired)
            XCTAssertEqual(store.state.portfolio, refreshed)
            XCTAssertTrue(store.state.orderEditor?.needsReview == true)
            XCTAssertEqual(writes.value, 1)
        }
    }

    func testValidationAndStateConflictPreserveDraftWithoutReplay() async throws {
        for (code, issue) in [
            ("validation_error", ATADashboardFeature.MutationIssue.validation),
            ("state_conflict", .stateConflict),
        ] {
            let current = try portfolio
            let writes = LockIsolated(0)
            let failure = error(code == "validation_error" ? 422 : 409, code)
            let store = TestStore(initialState: loaded(current)) {
                ATADashboardFeature()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.ataClient.confirmLimitOrderFilled = { _, _ in
                    writes.withValue { $0 += 1 }
                    throw failure
                }
            }
            store.exhaustivity = .off
            await store.send(.confirmExternalFillTapped(current.limitOrders[0].id))
            await store.send(.orderSettlementChanged(.usdc))
            await store.send(.orderEditorSubmitTapped)
            await store.receive(.mutationFinished(generation: 1, result: .failed(issue)))
            XCTAssertEqual(store.state.portfolio, current)
            XCTAssertNotNil(store.state.orderEditor)
            XCTAssertEqual(store.state.orderEditor?.needsReview, issue == .stateConflict)
            XCTAssertEqual(writes.value, 1)
        }

    }

    func testMissingOrderAfterReconciliationCannotResubmitOldFill() async throws {
        let current = try portfolio
        let refreshed = response(current, revision: 8, orders: [])
        let gate = OrderGate()
        let writes = LockIsolated(0)
        let missing = error(404, "resource_not_found")
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.ataClient.confirmLimitOrderFilled = { _, _ in
                writes.withValue { $0 += 1 }
                throw missing
            }
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
            $0.ataClient.loadPortfolio = { await gate.wait() }
        }
        store.exhaustivity = .off
        await store.send(.confirmExternalFillTapped(current.limitOrders[0].id))
        await store.send(.orderSettlementChanged(.usdc))
        await store.send(.orderEditorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .failed(.resourceNotFound)))
        await gate.resolve(refreshed)
        await store.receive(.loadFinished(generation: 2, result: .loaded(refreshed)))
        await store.send(.editorReviewAcknowledged)
        await store.send(.orderEditorSubmitTapped)
        XCTAssertEqual(store.state.orderEditor?.inputError, .orderNotOpen)
        XCTAssertEqual(writes.value, 1)
    }

    func testCredentialChangeInvalidatesLateOrderResponseAndDiscardsDraft() async throws {
        let current = try portfolio
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.createLimitOrder = { _ in
                try await Task.sleep(for: .seconds(30))
                return current
            }
            $0.ataCredentials.delete = {}
            $0.ataCredentials.load = { throw CredentialStoreError.tokenAbsent }
        }
        store.exhaustivity = .off
        await store.send(.createLimitOrderTapped)
        await store.send(.orderTargetPriceChanged("10"))
        await store.send(.orderQuantityChanged("1"))
        await store.send(.orderEditorSubmitTapped)
        await store.send(.credentialDeleteRequested)
        XCTAssertNil(store.state.orderEditor)
        XCTAssertNil(store.state.portfolio)
        await store.send(.mutationFinished(generation: 1, result: .succeeded(current)))
        XCTAssertNil(store.state.portfolio)
    }

    func testOrderWriteBlocksAccountAndPolicyWritesAndDuplicateSubmission() async throws {
        let current = try portfolio
        let returned = response(current, revision: 8)
        let gate = OrderGate()
        let writes = LockIsolated(0)
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.createLimitOrder = { _ in
                writes.withValue { $0 += 1 }
                return await gate.wait()
            }
        }
        store.exhaustivity = .off
        await store.send(.createLimitOrderTapped)
        await store.send(.orderTargetPriceChanged("50"))
        await store.send(.orderQuantityChanged("0.1"))
        await store.send(.orderEditorSubmitTapped)
        XCTAssertEqual(store.state.mutationInFlight, .createLimitOrder)
        await store.send(.orderEditorSubmitTapped)
        await store.send(.createAccountTapped)
        await store.send(.editFinancialSettingsTapped)
        await store.send(.orderLifecycleTapped(current.limitOrders[0].id, .cancel))
        XCTAssertNil(store.state.editor)
        XCTAssertNil(store.state.policyEditor)
        XCTAssertNil(store.state.orderLifecycle)
        XCTAssertEqual(writes.value, 1)
        await gate.resolve(returned)
        await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
    }

    func testAccountAndPolicyWritesBlockOrderWrites() async throws {
        for accountWrite in [true, false] {
            let current = try portfolio
            let returned = response(current, revision: 8)
            let gate = OrderGate()
            let orderWrites = LockIsolated(0)
            let store = TestStore(initialState: loaded(current)) {
                ATADashboardFeature()
            } withDependencies: {
                $0.ataClient.createAccount = { _ in await gate.wait() }
                $0.ataClient.updateFinancialSettings = { _ in await gate.wait() }
                $0.ataClient.createLimitOrder = { _ in
                    orderWrites.withValue { $0 += 1 }
                    return current
                }
            }
            store.exhaustivity = .off
            if accountWrite {
                await store.send(.createAccountTapped)
                await store.send(.editorNameChanged("New"))
                await store.send(.editorSubmitTapped)
            } else {
                await store.send(.editFinancialSettingsTapped)
                await store.send(.policyFirstValueChanged("300"))
                await store.send(.policyEditorSubmitTapped)
            }
            await store.send(.createLimitOrderTapped)
            await store.send(.orderLifecycleTapped(current.limitOrders[0].id, .expire))
            XCTAssertNil(store.state.orderEditor)
            XCTAssertNil(store.state.orderLifecycle)
            XCTAssertEqual(orderWrites.value, 0)
            await gate.resolve(returned)
            await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
        }
    }

    func testOlderGETCannotOverwriteOrderMutationResponse() async throws {
        let current = try portfolio
        let returned = response(current, revision: 8)
        let gate = OrderGate()
        let store = TestStore(initialState: loaded(current)) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataClient.createLimitOrder = { _ in returned }
            $0.ataClient.loadPortfolio = { await gate.wait() }
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
        }
        store.exhaustivity = .off
        await store.send(.refreshTapped)
        let oldGeneration = store.state.requestGeneration
        await store.send(.createLimitOrderTapped)
        await store.send(.orderTargetPriceChanged("50"))
        await store.send(.orderQuantityChanged("0.1"))
        await store.send(.orderEditorSubmitTapped)
        await store.receive(.mutationFinished(generation: 1, result: .succeeded(returned)))
        await store.send(.loadFinished(generation: oldGeneration, result: .loaded(current)))
        XCTAssertEqual(store.state.portfolio, returned)
        await gate.resolve(current)
    }
}

private actor OrderGate {
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
