import Foundation

/// A Realtime Database value. Records are kept as raw JSON so that fields this app does not
/// know about survive a save untouched (the web app and its rules depend on them).
enum JSON: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    /// Converts what the Firebase SDK hands back (NSNumber, NSString, NSArray, NSDictionary, NSNull).
    init(firebase value: Any?) {
        switch value {
        case nil, is NSNull:
            self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let text as String:
            self = .string(text)
        case let list as [Any]:
            self = .array(list.map { JSON(firebase: $0) })
        case let dict as [String: Any]:
            self = .object(dict.mapValues { JSON(firebase: $0) })
        default:
            self = .null
        }
    }

    /// The value in the form `setValue` / `updateChildValues` expect. Null deletes the node.
    var firebaseValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value):
            if value.rounded() == value, abs(value) < 1e15 { return Int64(value) }
            return value
        case .string(let value): return value
        case .array(let values): return values.map(\.firebaseValue)
        case .object(let values): return values.mapValues(\.firebaseValue)
        }
    }

    var isNull: Bool { self == .null }

    /// Strings as they are; numbers without a trailing ".0" (fields like `semanas` exist in both forms).
    var text: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
            return String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    var number: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    var int: Int? { number.map { Int($0) } }

    /// JavaScript truthiness, which the web app relies on for flags like `inhabilitado`.
    var truthy: Bool {
        switch self {
        case .null: return false
        case .bool(let value): return value
        case .number(let value): return value != 0 && !value.isNaN
        case .string(let value): return !value.isEmpty
        case .array, .object: return true
        }
    }

    /// Firebase turns arrays with gaps into objects keyed by index; both read as a list.
    var list: [JSON]? {
        switch self {
        case .array(let values): return values.filter { !$0.isNull }
        case .object(let values):
            return values.sorted { (Int($0.key) ?? .max, $0.key) < (Int($1.key) ?? .max, $1.key) }.map(\.value)
        default: return nil
        }
    }

    var object: [String: JSON]? {
        if case .object(let values) = self { return values }
        return nil
    }

    subscript(key: String) -> JSON? {
        object?[key]
    }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension JSON {
    static func from(_ text: String?) -> JSON { text.map(JSON.string) ?? .null }
    static func from(_ value: Int?) -> JSON { value.map { .number(Double($0)) } ?? .null }
    static func from(_ list: [Int]) -> JSON { .array(list.map { .number(Double($0)) }) }
}
