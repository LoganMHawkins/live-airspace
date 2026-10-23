import Foundation

/// Something worth a heads-up when it flies into range.
public struct WatchRule: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Three-letter ICAO airline code at the start of the callsign (ACA, BAW, UAE…).
        case airline
        /// ICAO type designator (A388, B744, A3ST…).
        case type
        /// Aircraft registration (C-GITS, N12345…).
        case registration
    }

    public var kind: Kind
    public var value: String
    public var label: String

    public var id: String { "\(kind.rawValue):\(value.uppercased())" }

    public init(kind: Kind, value: String, label: String? = nil) {
        self.kind = kind
        self.value = value.trimmingCharacters(in: .whitespaces).uppercased()
        self.label = label ?? self.value
    }

    public func matches(_ ac: Aircraft) -> Bool {
        switch kind {
        case .airline:
            guard let cs = ac.callsign, cs.count >= 4, cs.prefix(3).allSatisfy(\.isLetter), cs.dropFirst(3).first?.isNumber == true else { return false }
            return cs.prefix(3).uppercased() == value
        case .type:
            return ac.typeCode?.uppercased() == value
        case .registration:
            return ac.registration?.uppercased() == value
        }
    }

    /// Ready-made rules the settings screen offers.
    public static let suggestions: [WatchRule] = [
        .init(kind: .type, value: "A388", label: "Airbus A380"),
        .init(kind: .type, value: "B748", label: "Boeing 747-8"),
        .init(kind: .type, value: "B744", label: "Boeing 747-400"),
        .init(kind: .type, value: "A3ST", label: "Airbus Beluga"),
        .init(kind: .type, value: "B789", label: "Boeing 787-9"),
        .init(kind: .type, value: "A359", label: "Airbus A350-900"),
        .init(kind: .airline, value: "ACA", label: "Air Canada"),
        .init(kind: .airline, value: "WJA", label: "WestJet"),
        .init(kind: .airline, value: "UAE", label: "Emirates"),
        .init(kind: .airline, value: "BAW", label: "British Airways"),
    ]
}

public struct WatchAlert: Sendable, Equatable, Identifiable {
    public var id: String
    public var rule: WatchRule
    public var aircraftName: String
    public var typeCode: String?
    public var since: Date
}
