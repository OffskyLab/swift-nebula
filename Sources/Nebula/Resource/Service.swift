//
//  Service.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NMTP

public actor Service {
    public let name: String
    public let version: String?
    public internal(set) var methods: [String: any Method] = [:]

    public init(name: String, version: String? = nil) {
        self.name = name
        self.version = version
    }
}

// MARK: - Method Management

extension Service {

    public func add(method: ServiceMethod) {
        methods[method.name] = method
    }

    public func add(method name: String, action: @escaping MethodAction) {
        methods[name] = ServiceMethod(name: name, action: action)
    }
}

// MARK: - Invocation

extension Service {

    public func perform(method name: String, with arguments: [Argument]) async throws -> Data? {
        guard let method = methods[name] else {
            throw NebulaError.methodNotFound(service: self.name, method: name)
        }
        return try await method.invoke(arguments: arguments)
    }
}
