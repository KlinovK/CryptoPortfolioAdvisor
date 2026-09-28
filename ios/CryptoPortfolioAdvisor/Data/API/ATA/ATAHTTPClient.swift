import Foundation

private struct ATAHTTPClient: Sendable {
    let baseURL: URL
    let credentials: CredentialStore
    let transport: ATAHTTPTransport

    func read<DTO: Decodable & Sendable, Value: Sendable>(
        _ path: [String], limit: Int? = nil, dto: DTO.Type,
        map: @Sendable (DTO) throws -> Value
    ) async throws -> Value {
        if let limit, limit <= 0 { throw ATAClientError.invalidRequest }
        return try await perform(
            path, method: "GET", limit: limit, body: nil, success: 200, dto: dto, map: map)
    }

    func write<Body: Encodable & Sendable>(
        _ path: [String], method: String, body: Body, success: Int = 200
    ) async throws -> ATACurrentPortfolio {
        let data: Data
        do { data = try JSONEncoder().encode(body) } catch { throw ATAClientError.invalidRequest }
        return try await perform(
            path, method: method, body: data, success: success,
            dto: ATACurrentPortfolioDTO.self, map: { try ATAResponseMapper.domain(from: $0) })
    }

    private func perform<DTO: Decodable & Sendable, Value: Sendable>(
        _ path: [String], method: String, limit: Int? = nil, body: Data?, success: Int,
        dto: DTO.Type, map: @Sendable (DTO) throws -> Value
    ) async throws -> Value {
        if Task.isCancelled { throw ATAClientError.cancelled }
        var endpoint = baseURL
        for component in ["v1"] + path {
            // All components come from fixed routes, canonical UUIDs, or validated symbols.
            guard !component.isEmpty, component != ".", component != "..",
                !component.contains("/"), !component.contains("\\")
            else { throw ATAClientError.invalidRequest }
            endpoint.appendPathComponent(component)
        }
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ATAClientError.invalidConfiguration
        }
        components.queryItems = limit.map { [URLQueryItem(name: "limit", value: String($0))] }
        guard let url = components.url, sameOrigin(url, baseURL) else {
            throw ATAClientError.invalidConfiguration
        }
        let token: ATABearerToken
        do { token = try await credentials.load() } catch {
            if Task.isCancelled || error is CancellationError
                || (error as? URLError)?.code == .cancelled
            {
                throw ATAClientError.cancelled
            }
            if error as? CredentialStoreError == .tokenAbsent {
                throw ATAClientError.missingCredential
            }
            throw ATAClientError.credentialUnavailable
        }
        if Task.isCancelled { throw ATAClientError.cancelled }
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: ATAURLSessionTransport.timeout)
        request.httpMethod = method
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token.authorizationHeader, forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        let mutation = method != "GET"
        let data: Data
        let response: URLResponse
        // Conservatively treat transport handoff as possibly transmitted. No retries of any verb.
        do { (data, response) = try await transport.send(request) } catch {
            if Task.isCancelled || error is CancellationError
                || (error as? URLError)?.code == .cancelled
            {
                throw mutation ? ATAClientError.uncertainMutationOutcome(.cancelled) : .cancelled
            }
            let timedOut = (error as? URLError)?.code == .timedOut
            throw mutation
                ? ATAClientError.uncertainMutationOutcome(timedOut ? .timeout : .connection)
                : .transport(timedOut ? .timeout : .connection)
        }
        if Task.isCancelled {
            throw mutation ? ATAClientError.uncertainMutationOutcome(.cancelled) : .cancelled
        }
        guard let http = response as? HTTPURLResponse, http.url == url else {
            throw invalidResponse(mutation)
        }
        if (300...399).contains(http.statusCode) {
            throw mutation ? ATAClientError.uncertainMutationOutcome(.redirect) : .invalidResponse
        }
        if !(200...299).contains(http.statusCode) {
            guard let envelope = try? JSONDecoder().decode(ATAErrorEnvelopeDTO.self, from: data)
            else {
                throw invalidResponse(mutation)
            }
            let mapped = ATAResponseMapper.domain(from: envelope)
            // Preserve semantic codes/reload instructions, not untrusted server prose.
            // Even an error envelope that echoes the submitted credential cannot expose it.
            let safe = ATAServiceError(
                code: token.redacting(from: mapped.code),
                message: "ATA rejected the request.", reloadRequired: mapped.reloadRequired)
            let failure = ATAHTTPFailure(statusCode: http.statusCode, error: safe)
            if mutation && http.statusCode >= 500 {
                // A server failure may occur after commit while constructing the response.
                throw ATAClientError.uncertainMutationOutcome(.serverFailure, server: failure)
            }
            throw ATAClientError.http(failure)
        }
        guard http.statusCode == success else { throw invalidResponse(mutation) }
        do { return try map(JSONDecoder().decode(dto, from: data)) } catch {
            throw invalidResponse(mutation)
        }
    }

    private func invalidResponse(_ mutation: Bool) -> ATAClientError {
        mutation ? .uncertainMutationOutcome(.invalidResponse) : .invalidResponse
    }

    private func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && (lhs.port ?? (lhs.scheme == "https" ? 443 : 80))
                == (rhs.port ?? (rhs.scheme == "https" ? 443 : 80))
    }

    static func id(_ value: UUID) throws -> String {
        do { return try ATAResponseMapper.identity(value.uuidString).uuidString.lowercased() } catch
        { throw ATAClientError.invalidRequest }
    }
}

extension ATAClient {
    static func live(
        configuredBaseURL: String?, environment: ATAAPIEnvironment,
        credentials: CredentialStore, transport: ATAHTTPTransport? = nil
    ) throws -> Self {
        let baseURL: URL
        do {
            baseURL = try ATAAPIConfiguration.baseURL(
                configuredValue: configuredBaseURL, environment: environment)
        } catch { throw ATAClientError.invalidConfiguration }
        let http = ATAHTTPClient(
            baseURL: baseURL, credentials: credentials,
            transport: transport ?? ATAURLSessionTransport().transport)
        return Self(
            loadPortfolio: {
                try await http.read(
                    ["portfolio"], dto: ATACurrentPortfolioDTO.self,
                    map: { try ATAResponseMapper.domain(from: $0) })
            },
            loadLatestAnalysis: {
                try await http.read(
                    ["analyses", "latest"], dto: ATAAnalysisDetailDTO.self,
                    map: { try ATAResponseMapper.domain(from: $0) })
            },
            loadAnalyses: {
                try await http.read(
                    ["analyses"], limit: $0, dto: ATARecentAnalysesDTO.self,
                    map: { try ATAResponseMapper.domain(from: $0) })
            },
            loadAnalysis: {
                try await http.read(
                    ["analyses", ATAHTTPClient.id($0)], dto: ATAAnalysisDetailDTO.self,
                    map: { try ATAResponseMapper.domain(from: $0) })
            },
            createAccount: {
                try await http.write(
                    ["portfolio", "accounts"], method: "POST", body: $0, success: 201)
            },
            renameAccount: {
                try await http.write(
                    ["portfolio", "accounts", ATAHTTPClient.id($0)], method: "PATCH", body: $1)
            },
            updateAccountHoldings: {
                try await http.write(
                    ["portfolio", "accounts", ATAHTTPClient.id($0), "holdings"], method: "PUT",
                    body: $1)
            },
            deleteAccount: {
                try await http.write(
                    ["portfolio", "accounts", ATAHTTPClient.id($0)], method: "DELETE", body: $1)
            },
            updateFinancialSettings: {
                try await http.write(["portfolio", "financial-settings"], method: "PUT", body: $0)
            },
            updateCorePosition: {
                try await http.write(
                    ["portfolio", "core-positions", $0.rawValue], method: "PUT", body: $1)
            },
            createLimitOrder: {
                try await http.write(
                    ["portfolio", "orders"], method: "POST", body: $0, success: 201)
            },
            cancelLimitOrder: {
                try await http.write(
                    ["portfolio", "orders", ATAHTTPClient.id($0), "cancel"], method: "POST",
                    body: $1)
            },
            expireLimitOrder: {
                try await http.write(
                    ["portfolio", "orders", ATAHTTPClient.id($0), "expire"], method: "POST",
                    body: $1)
            },
            confirmLimitOrderFilled: {
                try await http.write(
                    ["portfolio", "orders", ATAHTTPClient.id($0), "confirm-filled"], method: "POST",
                    body: $1)
            }
        )
    }
}
