//
//  NebulaURI.swift
//
//
//  Created by Grady Zhuo on 2026/3/23.
//

import Foundation

/// Represents an `nmtp://` connection URI used to locate a namespace via Galaxy.
///
/// Namespace segments are expressed as path components in forward order (discovery path):
/// `{galaxy}/{amas}/{stellar}` — broadest first, most specific last.
///
/// ```
/// nmtp://localhost:22400/production/ml/embedding
///        └─────────────┘ └────────┘ └┘ └───────┘
///        Galaxy address  galaxy    amas stellar
/// ```
///
/// Path segments are joined with `.` to form the namespace string `production.ml.embedding`.
public struct NebulaURI: Sendable {
    public static let scheme = "nmtp"

    public let user: String?
    public let password: String?

    /// Galaxy host address (e.g. `localhost`, `192.168.1.1`, `::1`).
    public let galaxyHost: String
    /// Galaxy port (e.g. `22400`).
    public let galaxyPort: Int

    /// The service namespace in forward order (e.g. `production.ml.embedding`).
    public let namespace: String

    /// Galaxy name — first dot-separated segment of namespace.
    /// e.g. `"production"` from `"production.ml.embedding"`.
    public var galaxyName: String {
        String(namespace.split(separator: ".").first ?? Substring(namespace))
    }

    public init(_ string: String) throws {
        guard let components = URLComponents(string: string),
              components.scheme == Self.scheme else {
            throw NebulaError.invalidURI("URI must use nmtp:// scheme: \(string)")
        }

        guard let host = components.host, !host.isEmpty else {
            throw NebulaError.invalidURI("Missing Galaxy host in URI: \(string)")
        }

        guard let port = components.port else {
            throw NebulaError.invalidURI("Missing Galaxy port in URI: \(string)")
        }

        user     = components.user
        password = components.password

        // Strip IPv6 brackets (e.g. "[::1]" → "::1")
        galaxyHost = host.hasPrefix("[") && host.hasSuffix("]")
            ? String(host.dropFirst().dropLast())
            : host
        galaxyPort = port

        let pathParts = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard !pathParts.isEmpty else {
            throw NebulaError.invalidURI("Missing namespace in URI: \(string)")
        }

        namespace = pathParts.joined(separator: ".")
    }
}
