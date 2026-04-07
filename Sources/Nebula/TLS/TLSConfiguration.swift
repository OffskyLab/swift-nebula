// Sources/Nebula/TLS/TLSConfiguration.swift
import Foundation

/// CA + identity certificate configuration for a single Nebula node.
///
/// All nodes in a cluster share the same CA (for mutual verification),
/// but each node has its own identity certificate.
public struct NebulaTLSConfiguration: Sendable {
    /// The certificate authority used to verify the peer's certificate.
    public let ca: CACertificateSource
    /// This node's identity: its own certificate and private key.
    public let identity: IdentitySource

    public init(ca: CACertificateSource, identity: IdentitySource) {
        self.ca = ca
        self.identity = identity
    }
}

/// Where to load the CA certificate from.
public enum CACertificateSource: Sendable {
    /// Path to a PEM-encoded CA certificate file on disk.
    case file(path: String)
    /// PEM-encoded CA certificate bytes in memory.
    case pem(Data)
}

/// Where to load the node's identity (cert + private key) from.
public enum IdentitySource: Sendable {
    /// Paths to PEM-encoded certificate and unencrypted private key files on disk.
    case files(cert: String, key: String)
    /// PEM-encoded certificate and unencrypted private key bytes in memory.
    case pem(cert: Data, key: Data)
}
