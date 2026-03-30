//
//  RetryPolicy.swift
//
//
//  Created by Grady Zhuo on 2026/3/30.
//

import Foundation

public struct RetryPolicy: Sendable {
    public let maxRetries: Int
    public let ackTimeout: Duration

    public init(maxRetries: Int, ackTimeout: Duration) {
        self.maxRetries = maxRetries
        self.ackTimeout = ackTimeout
    }

    public static let `default` = RetryPolicy(maxRetries: 3, ackTimeout: .seconds(30))
}
