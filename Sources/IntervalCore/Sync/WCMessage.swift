import Foundation

/// The one envelope both apps put on the wire. Encodes to a property-list-safe
/// dictionary (`type`, `v`, `payload` as JSON `Data`), which `sendMessage`,
/// `transferUserInfo`, and `updateApplicationContext` all accept. Large messages
/// (`SessionResult`) go through `transferFile` instead: see `fileTransfer()`.
public enum WCMessage: Hashable, Sendable {
    case command(SessionCommand)
    case liveSample(LiveSample)
    case sessionResult(SessionResult)
    /// Watch → phone HR for a phone-only session (~1 Hz via `sendMessage`), started by
    /// `SessionCommand.heartRateStream(enabled:)`.
    case heartRate(HeartRateReading)

    public static let schemaVersion = 1

    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case command
        case liveSample
        case sessionResult
        case heartRate
    }

    public enum DecodingError: Error, Hashable, Sendable {
        case missingType
        case unknownType(String)
        case missingVersion
        /// Sent by a newer app version than this one understands.
        case unsupportedVersion(Int)
        case missingPayload
        case invalidPayload(String)
    }

    public enum Key {
        public static let type = "type"
        public static let version = "v"
        public static let payload = "payload"
        /// File-transfer metadata only: lets the receiver dedupe a result before decoding it.
        public static let sessionID = "sessionID"
    }

    public var kind: Kind {
        switch self {
        case .command: .command
        case .liveSample: .liveSample
        case .sessionResult: .sessionResult
        case .heartRate: .heartRate
        }
    }

    public func toDictionary() throws -> [String: Any] {
        [Key.type: kind.rawValue, Key.version: Self.schemaVersion, Key.payload: try payloadData()]
    }

    public init(dictionary: [String: Any]) throws {
        // Version first: a newer schema may add types this build has never heard of.
        guard let version = dictionary[Key.version] as? Int else { throw DecodingError.missingVersion }
        guard version <= Self.schemaVersion else { throw DecodingError.unsupportedVersion(version) }
        guard let rawType = dictionary[Key.type] as? String else { throw DecodingError.missingType }
        guard let kind = Kind(rawValue: rawType) else { throw DecodingError.unknownType(rawType) }
        guard let payload = dictionary[Key.payload] as? Data else { throw DecodingError.missingPayload }

        let decoder = JSONDecoder()
        do {
            switch kind {
            case .command: self = .command(try decoder.decode(SessionCommand.self, from: payload))
            case .liveSample: self = .liveSample(try decoder.decode(LiveSample.self, from: payload))
            case .sessionResult: self = .sessionResult(try decoder.decode(SessionResult.self, from: payload))
            case .heartRate: self = .heartRate(try decoder.decode(HeartRateReading.self, from: payload))
            }
        } catch {
            throw DecodingError.invalidPayload(String(describing: error))
        }
    }

    // MARK: - transferFile

    /// File contents plus `transferFile` metadata (`type`, `v`, and `sessionID` for results).
    /// No size limit, so a `SessionResult` keeps its full 5 s HR series at any length.
    public func fileTransfer() throws -> (data: Data, metadata: [String: Any]) {
        var metadata: [String: Any] = [Key.type: kind.rawValue, Key.version: Self.schemaVersion]
        if case .sessionResult(let result) = self {
            metadata[Key.sessionID] = result.sessionID.uuidString
        }
        return (try payloadData(), metadata)
    }

    /// Decodes a received file. `metadata` is `WCSessionFile.metadata`; a missing one
    /// throws `missingVersion`, like an envelope without `v`.
    public init(fileData: Data, metadata: [String: Any]?) throws {
        var dictionary = metadata ?? [:]
        dictionary[Key.payload] = fileData
        try self.init(dictionary: dictionary)
    }

    /// Reads the file at `fileURL` (from `WCSessionFile.fileURL`, which is only valid
    /// during the delegate callback) and decodes it.
    public init(fileURL: URL, metadata: [String: Any]?) throws {
        try self.init(fileData: Data(contentsOf: fileURL), metadata: metadata)
    }

    /// Session id from `transferFile` metadata, without decoding the file.
    public static func sessionID(fromMetadata metadata: [String: Any]?) -> UUID? {
        (metadata?[Key.sessionID] as? String).flatMap(UUID.init(uuidString:))
    }

    private func payloadData() throws -> Data {
        let encoder = JSONEncoder()
        return switch self {
        case .command(let value): try encoder.encode(value)
        case .liveSample(let value): try encoder.encode(value)
        case .sessionResult(let value): try encoder.encode(value)
        case .heartRate(let value): try encoder.encode(value)
        }
    }
}
