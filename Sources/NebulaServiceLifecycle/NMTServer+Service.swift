//
//  NMTServer+Service.swift
//
//
//  Created by Grady Zhuo on 2026/3/23.
//

import Nebula
import ServiceLifecycle

extension NMTServer: ServiceLifecycle.Service {
    public func run() async throws {
        try await listen()
    }
}
