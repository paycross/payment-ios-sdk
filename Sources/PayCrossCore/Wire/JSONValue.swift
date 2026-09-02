import Foundation

/// A JSON value carried through the SDK without being understood.
///
/// Apple's payment token is the only thing that needs this, and it needs it
/// for a specific reason: the SDK is not the last reader of that object. The
/// edge looks for `paymentData`, the vault reads four fields inside it, and
/// Apple may add a fifth without telling anyone. Modelling the token as a
/// `Codable` struct would silently drop whatever the struct did not name, and
/// the symptom would be a decryption failure with no field to point at.
///
/// Integers decode as integers rather than through `Double`, so a long numeric
/// field cannot come back in exponent notation.
package enum JSONValue: Codable, Sendable, Hashable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case null

    package init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "not a JSON value"
            )
        }
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
