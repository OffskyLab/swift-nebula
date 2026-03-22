//
//  NebulaURI.swift
//
//
//  Created by Grady Zhuo on 2026/3/23.
//

import Foundation

/// Represents an `nmtp://` URI used to address a service endpoint.
///
/// Two resolution modes depending on whether a port is present:
///
/// **Discovery mode** (no port — recommended):
/// ```
/// nmtp://production.ml.embedding/w2v/wordVector
///        └─────────────────────┘ └──┘ └────────┘
///        namespace               svc  method
///        galaxyName = "production" → resolved via Nebula.discovery
/// ```
///
/// **Explicit address mode** (with port — no Discovery needed):
/// ```
/// nmtp://[::1]:9000/production.ml.embedding/w2v/wordVector
///        └────────┘ └─────────────────────┘ └──┘ └────────┘
///        Galaxy addr  namespace              svc  method
/// ```
///
/// Query string arguments support JSON strings, numbers, booleans, and arrays.
public struct NebulaURI: Sendable {
    public static let scheme = "nmtp"

    public let user: String?
    public let password: String?

    /// The service namespace (e.g. `production.ml.embedding`).
    public let namespace: String
    /// Service name (e.g. `w2v`).
    public let service: String?
    /// Method name (e.g. `wordVector`).
    public let method: String?
    /// Arguments from query string.
    public let arguments: [Argument]

    /// Galaxy name for Discovery resolution — first dot-separated segment of namespace.
    /// e.g. `"production"` from `"production.ml.embedding"`.
    public var galaxyName: String {
        String(namespace.prefix(while: { $0 != "." }))
    }

    /// Explicit Galaxy host, present only when a port is included in the URI.
    public let explicitGalaxyHost: String?
    /// Explicit Galaxy port, present only when a port is included in the URI.
    public let explicitGalaxyPort: Int?

    public init(_ string: String) throws {
        guard let components = URLComponents(string: string),
              components.scheme == Self.scheme else {
            throw NebulaError.invalidURI("URI must use nmtp:// scheme: \(string)")
        }

        guard let host = components.host, !host.isEmpty else {
            throw NebulaError.invalidURI("Missing host in URI: \(string)")
        }

        user     = components.user
        password = components.password

        let pathParts = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        if let port = components.port {
            // Explicit address mode: host = Galaxy, path = [namespace, service, method]
            explicitGalaxyHost = host
            explicitGalaxyPort = port
            namespace = pathParts.count > 0 ? pathParts[0] : host
            service   = pathParts.count > 1 ? pathParts[1] : nil
            method    = pathParts.count > 2 ? pathParts[2] : nil
        } else {
            // Discovery mode: host = namespace, path = [service, method]
            explicitGalaxyHost = nil
            explicitGalaxyPort = nil
            namespace = host
            service   = pathParts.count > 0 ? pathParts[0] : nil
            method    = pathParts.count > 1 ? pathParts[1] : nil
        }

        arguments = try (components.queryItems ?? []).map { item in
            try NebulaURI.parseArgument(key: item.name, rawValue: item.value ?? "")
        }
    }
}

// MARK: - Argument Parsing

extension NebulaURI {

    private static func parseArgument(key: String, rawValue: String) throws -> Argument {
        if let data = rawValue.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
            return try Argument.wrap(key: key, value: ArgumentValue(jsonObject))
        }
        return try Argument.wrap(key: key, value: rawValue)
    }
}
