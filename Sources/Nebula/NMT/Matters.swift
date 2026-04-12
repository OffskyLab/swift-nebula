// Sources/Nebula/NMT/Matters.swift

import Foundation
import NMTP

// MARK: - Clone (0x0001)

public struct CloneMatter: MatterBehavior {
    public static let typeID: UInt16 = 0x0001
    public static let type: MatterType = .query
    public init() {}
}

public struct CloneReplyMatter: Codable, Sendable {
    public var identifier: String
    public var name: String
    public var category: UInt8
    public init(identifier: String, name: String, category: UInt8) {
        self.identifier = identifier; self.name = name; self.category = category
    }
}

extension MatterBehavior where Self == CloneMatter {
    public static func clone() -> CloneMatter { CloneMatter() }
}

// MARK: - Register (0x0002)

public struct RegisterMatter: MatterBehavior {
    public static let typeID: UInt16 = 0x0002
    public static let type: MatterType = .command
    public var namespace: String
    public var host: String
    public var port: Int
    public var identifier: String
    public init(namespace: String, host: String, port: Int, identifier: String) {
        self.namespace = namespace; self.host = host; self.port = port; self.identifier = identifier
    }
}

public struct RegisterReplyMatter: Codable, Sendable {
    public var status: String
    public init(status: String) { self.status = status }
}

extension MatterBehavior where Self == RegisterMatter {
    public static func register(
        namespace: String, host: String, port: Int, identifier: String
    ) -> RegisterMatter {
        RegisterMatter(namespace: namespace, host: host, port: port, identifier: identifier)
    }
}

// MARK: - Find (0x0003)

public struct FindMatter: MatterBehavior {
    public static let typeID: UInt16 = 0x0003
    public static let type: MatterType = .query
    public var namespace: String
    public init(namespace: String) { self.namespace = namespace }
}

public struct FindReplyMatter: Codable, Sendable {
    public var stellarHost: String?
    public var stellarPort: Int?
    public init(stellarHost: String? = nil, stellarPort: Int? = nil) {
        self.stellarHost = stellarHost; self.stellarPort = stellarPort
    }
}

extension MatterBehavior where Self == FindMatter {
    public static func find(namespace: String) -> FindMatter { FindMatter(namespace: namespace) }
}

// MARK: - FindGalaxy (0x000E)

public struct FindGalaxyMatter: MatterBehavior {
    public static let typeID: UInt16 = 0x000E
    public static let type: MatterType = .query
    public var topic: String
    public init(topic: String) { self.topic = topic }
}

public struct FindGalaxyReplyMatter: Codable, Sendable {
    public var galaxyHost: String?
    public var galaxyPort: Int?
    public init(galaxyHost: String? = nil, galaxyPort: Int? = nil) {
        self.galaxyHost = galaxyHost; self.galaxyPort = galaxyPort
    }
}

extension MatterBehavior where Self == FindGalaxyMatter {
    public static func findGalaxy(topic: String) -> FindGalaxyMatter { FindGalaxyMatter(topic: topic) }
}

// MARK: - Unregister (0x0008)

public struct UnregisterMatter: MatterBehavior {
    public static let typeID: UInt16 = 0x0008
    public static let type: MatterType = .command
    public var namespace: String
    public var host: String
    public var port: Int
    public init(namespace: String, host: String, port: Int) {
        self.namespace = namespace; self.host = host; self.port = port
    }
}

public struct UnregisterReplyMatter: Codable, Sendable {
    public var nextHost: String?
    public var nextPort: Int?
    public init(nextHost: String? = nil, nextPort: Int? = nil) {
        self.nextHost = nextHost; self.nextPort = nextPort
    }
}

extension MatterBehavior where Self == UnregisterMatter {
    public static func unregister(namespace: String, host: String, port: Int) -> UnregisterMatter {
        UnregisterMatter(namespace: namespace, host: host, port: port)
    }
}

// MARK: - Call (0x0004)

public struct CallMatter: MatterBehavior {
    public static let typeID: UInt16 = 0x0004
    public static let type: MatterType = .command
    public var namespace: String
    public var service: String
    public var method: String
    public var arguments: [EncodedArgument]
    public init(namespace: String, service: String, method: String, arguments: [EncodedArgument] = []) {
        self.namespace = namespace; self.service = service
        self.method = method; self.arguments = arguments
    }
}

public struct CallReplyMatter: Codable, Sendable {
    public var result: Data?
    public var error: String?
    public init(result: Data? = nil, error: String? = nil) {
        self.result = result; self.error = error
    }
}

extension MatterBehavior where Self == CallMatter {
    public static func call(
        namespace: String, service: String, method: String, arguments: [EncodedArgument] = []
    ) -> CallMatter {
        CallMatter(namespace: namespace, service: service, method: method, arguments: arguments)
    }
}

// MARK: - Enqueue (0x0009)

public struct EnqueueMatter: MatterBehavior {
    public static let typeID: UInt16 = 0x0009
    public static let type: MatterType = .command
    public var namespace: String
    public var service: String
    public var method: String
    public var arguments: [EncodedArgument]
    public init(namespace: String, service: String, method: String, arguments: [EncodedArgument] = []) {
        self.namespace = namespace; self.service = service
        self.method = method; self.arguments = arguments
    }
}

public struct EnqueueReplyMatter: Codable, Sendable {
    public var status: String
    public init(status: String) { self.status = status }
}

extension MatterBehavior where Self == EnqueueMatter {
    public static func enqueue(
        namespace: String, service: String, method: String, arguments: [EncodedArgument] = []
    ) -> EnqueueMatter {
        EnqueueMatter(namespace: namespace, service: service, method: method, arguments: arguments)
    }
}

// MARK: - Ack (0x000A)

public struct AckMatter: MatterBehavior {
    public static let typeID: UInt16 = 0x000A
    public static let type: MatterType = .command
    public var matterID: String
    public init(matterID: String) { self.matterID = matterID }
}

extension MatterBehavior where Self == AckMatter {
    public static func ack(matterID: String) -> AckMatter { AckMatter(matterID: matterID) }
}

// MARK: - Subscribe (0x000B)

public struct SubscribeMatter: MatterBehavior {
    public static let typeID: UInt16 = 0x000B
    public static let type: MatterType = .command
    public var topic: String
    public var subscription: String
    public init(topic: String, subscription: String) {
        self.topic = topic; self.subscription = subscription
    }
}

public struct SubscribeReplyMatter: Codable, Sendable {
    public var status: String
    public init(status: String) { self.status = status }
}

extension MatterBehavior where Self == SubscribeMatter {
    public static func subscribe(topic: String, subscription: String) -> SubscribeMatter {
        SubscribeMatter(topic: topic, subscription: subscription)
    }
}

// MARK: - Unsubscribe (0x000C)

public struct UnsubscribeMatter: MatterBehavior {
    public static let typeID: UInt16 = 0x000C
    public static let type: MatterType = .command
    public var topic: String
    public var subscription: String
    public init(topic: String, subscription: String) {
        self.topic = topic; self.subscription = subscription
    }
}

extension MatterBehavior where Self == UnsubscribeMatter {
    public static func unsubscribe(topic: String, subscription: String) -> UnsubscribeMatter {
        UnsubscribeMatter(topic: topic, subscription: subscription)
    }
}

// MARK: - Event (0x000D)

public struct EventMatter: MatterBehavior {
    public static let typeID: UInt16 = 0x000D
    public static let type: MatterType = .event
    public var topic: String
    public var method: String
    public var arguments: [EncodedArgument]
    public init(topic: String, method: String, arguments: [EncodedArgument] = []) {
        self.topic = topic; self.method = method; self.arguments = arguments
    }
}

extension MatterBehavior where Self == EventMatter {
    public static func event(topic: String, method: String, arguments: [EncodedArgument] = []) -> EventMatter {
        EventMatter(topic: topic, method: method, arguments: arguments)
    }
}
