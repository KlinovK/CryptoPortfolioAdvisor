import Foundation

enum PortfolioAPIBuildEnvironment: Equatable, Sendable {
    case debug
    case release

    static var current: Self {
        #if DEBUG
        .debug
        #else
        .release
        #endif
    }
}

enum PortfolioAPIConfigurationError: Error, Equatable, Sendable {
    case missingBaseURL
    case invalidBaseURL
    case insecureReleaseURL
    case localReleaseURL
}

enum PortfolioAPIConfiguration {
    static let infoDictionaryKey = "CPA_BACKEND_BASE_URL"
    static let developmentBaseURL = URL(string: "http://127.0.0.1:8000")!

    static var currentBaseURL: URL {
        do {
            return try baseURL(
                configuredValue: Bundle.main.object(
                    forInfoDictionaryKey: infoDictionaryKey
                ) as? String,
                environment: .current
            )
        } catch {
            fatalError("Invalid backend URL configuration: \(error)")
        }
    }

    static func baseURL(
        configuredValue: String?,
        environment: PortfolioAPIBuildEnvironment
    ) throws -> URL {
        let normalized = configuredValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String
        if let normalized, !normalized.isEmpty {
            value = normalized
        } else if environment == .debug {
            return developmentBaseURL
        } else {
            throw PortfolioAPIConfigurationError.missingBaseURL
        }

        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let url = components.url
        else {
            throw PortfolioAPIConfigurationError.invalidBaseURL
        }

        if environment == .release {
            guard scheme == "https" else {
                throw PortfolioAPIConfigurationError.insecureReleaseURL
            }
            guard host != "localhost", host != "127.0.0.1", host != "::1" else {
                throw PortfolioAPIConfigurationError.localReleaseURL
            }
        } else if scheme != "http" && scheme != "https" {
            throw PortfolioAPIConfigurationError.invalidBaseURL
        }

        return url
    }
}

enum PortfolioAPIClientError: Error, Equatable, Sendable {
    case invalidResponse
    case server(statusCode: Int, code: String?, message: String)
    case decoding
    case timeout
    case transport
}

enum PortfolioAPIResponseDecoder {
    static func decode(data: Data, response: URLResponse) throws -> PortfolioAnalysis {
        guard let response = response as? HTTPURLResponse else {
            throw PortfolioAPIClientError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard (200 ... 299).contains(response.statusCode) else {
            let envelope = try? decoder.decode(PortfolioAPIErrorResponseDTO.self, from: data)
            throw PortfolioAPIClientError.server(
                statusCode: response.statusCode,
                code: envelope?.error.code,
                message: envelope?.error.message ?? "The server rejected the request."
            )
        }

        do {
            let dto = try decoder.decode(PortfolioAnalysisResponseDTO.self, from: data)
            return try PortfolioAPIMapper.domain(from: dto)
        } catch let error as PortfolioAPIMapperError {
            throw error
        } catch {
            throw PortfolioAPIClientError.decoding
        }
    }
}

extension PortfolioAnalysisClient {
    static func live(
        baseURL: URL = PortfolioAPIConfiguration.currentBaseURL,
        session: URLSession = .shared
    ) -> Self {
        Self { snapshot in
            let endpoint = baseURL
                .appendingPathComponent("v1")
                .appendingPathComponent("portfolio")
                .appendingPathComponent("analyze")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 50
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(PortfolioAPIMapper.request(from: snapshot))

            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                return try PortfolioAPIResponseDecoder.decode(data: data, response: response)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as URLError where error.code == .timedOut {
                throw PortfolioAPIClientError.timeout
            } catch let error as PortfolioAPIClientError {
                throw error
            } catch let error as PortfolioAPIMapperError {
                throw error
            } catch {
                throw PortfolioAPIClientError.transport
            }
        }
    }
}
