//
//  DemoTask.swift
//
//  Runs a sample Planet call after the servers are up,
//  then keeps running until Ctrl+C triggers graceful shutdown.
//

import Foundation
import Nebula
import ServiceLifecycle

struct VectorResult: Decodable {
    let vector: [Float]
}

struct DemoTask: ServiceLifecycle.Service {

    func run() async throws {
        // Give servers a moment to finish binding
        try await Task.sleep(for: .milliseconds(300))

        print("\n── Nebula Demo Call ──")

        let planet = try await Nebula.planet(
            connecting: "nmtp://[::1]:22400/production.ml.embedding/w2v"
        )

        let result = try await planet.call(
            method: "wordVector",
            arguments: [
                .wrap(key: "words", value: ["慢跑", "反光", "排汗", "乾爽"])
            ],
            as: VectorResult.self
        )

        print("Result:", result.vector)
        print("── Press Ctrl+C to stop ──\n")

        // Block until the ServiceGroup cancels this task (Ctrl+C / SIGTERM)
        try await Task.sleep(for: .seconds(60 * 60 * 24))
    }
}
