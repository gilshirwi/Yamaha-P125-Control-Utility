import Foundation

/// Yamaha Smart Pianist property identifiers. Only enable controls after the
/// connected P-125 has returned a value for the individual property and index.
public enum PianoProperty: UInt32, CaseIterable, Codable, Sendable {
    case model = 0x0F011801
    case firmware = 0x0F010B01
    case volume = 0x0C000001
    case pan = 0x0C000301
    case reverbSend = 0x0C000401
    case octave = 0x0C001201
    case voice = 0x02000101
    case voicePreset = 0x02000001
    case panelVoice = 0x02000301
    case active = 0x0C000101
    case reverbType = 0x0C010001
    case transpose = 0x0A000001
    case splitPoint = 0x09000001
    case masterTune = 0x03000001
    case touch = 0x00000001

    public var bytes: [UInt8] {
        [24,16,8,0].map { UInt8((rawValue >> $0) & 0xFF) }
    }
}

public struct ParameterKey: Hashable, Codable, Sendable {
    public let property: PianoProperty
    public let index: UInt8
    public init(_ property: PianoProperty, _ index: UInt8 = 0) {
        self.property = property; self.index = index
    }
}

public enum P125Parameters {
    /// Keyboard and song transposition are separate targets on the P-125.
    public static let keyboardTranspose = ParameterKey(.transpose,1)
    public static let songTranspose = ParameterKey(.transpose,2)
}

public struct PropertyReply: Equatable, Sendable {
    public let key: ParameterKey
    public let value: [UInt8]
    public let isAcknowledgement: Bool
    public let responseStatus: Int
    public var integer: Int { SmartPianist.decodeInteger(value) }
    public var string: String {
        String(bytes: value.filter { $0 != 0 }, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

public enum SmartPianist {
    public static let prefix: [UInt8] = [0xF0,0x43,0x73,0x01,0x52,0x25,0x26]

    public static func get(_ key: ParameterKey) -> [UInt8] {
        prefix + [0x01,0x00] + key.property.bytes + [key.index,0x01,0x00,0xF7]
    }

    public static func set(_ key: ParameterKey, value: [UInt8]) -> [UInt8]? {
        guard key.index < 0x80, !value.isEmpty, value.count < 16384, value.allSatisfy({ $0 < 0x80 }) else { return nil }
        return prefix + [0x01,0x01] + key.property.bytes + [key.index,0x01,0x00] + encodeInteger(value.count, count: 2) + value + [0xF7]
    }

    public static func subscribe(_ property: PianoProperty) -> [UInt8] {
        prefix + [0x02,0x00] + property.bytes + [0xF7]
    }

    public static func reset(_ key: ParameterKey) -> [UInt8] {
        prefix + [0x04,0x01] + key.property.bytes + [key.index,0x01,0x00,0xF7]
    }

    public static func encodeInteger(_ value: Int, count: Int) -> [UInt8] {
        guard count > 0, count <= 4 else { return [] }
        return (0..<count).reversed().map { UInt8((value >> ($0 * 7)) & 0x7F) }
    }

    public static func decodeInteger(_ bytes: [UInt8]) -> Int {
        guard bytes.count <= 4 else { return 0 }
        return bytes.reduce(0) { ($0 << 7) | Int($1) }
    }

    public static func parse(_ bytes: [UInt8]) -> PropertyReply? {
        guard bytes.count >= 19, Array(bytes.prefix(7)) == prefix, bytes.last == 0xF7,
              bytes.dropFirst().dropLast().allSatisfy({ $0 < 0x80 }), bytes[7] == 0,
              bytes[8] == 0 || bytes[8] == 1, bytes[14] == 1, bytes[15] == 0 else { return nil }
        let id = bytes[9..<13].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard let property = PianoProperty(rawValue: id) else { return nil }
        let acknowledged = bytes[8] == 1
        let lengthOffset = acknowledged ? 18 : 16
        guard bytes.count >= lengthOffset + 3 else { return nil }
        let count = decodeInteger(Array(bytes[lengthOffset..<(lengthOffset + 2)]))
        let dataStart = lengthOffset + 2
        guard bytes.count == dataStart + count + 1 else { return nil }
        let status = acknowledged ? decodeInteger(Array(bytes[16..<18])) : 0
        return PropertyReply(key: ParameterKey(property, bytes[13]), value: Array(bytes[dataStart..<(dataStart + count)]), isAcknowledgement: acknowledged,responseStatus:status)
    }
}

/// Reassembles MIDI 1.0 SysEx across packets. Realtime bytes may occur anywhere.
public struct SysExFramer {
    private var buffer: [UInt8] = []
    public init() {}
    public mutating func consume(_ bytes: [UInt8]) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        for byte in bytes {
            if byte >= 0xF8 { continue }
            if byte == 0xF0 { buffer = [byte] }
            else if byte == 0xF7 {
                if !buffer.isEmpty { buffer.append(byte); messages.append(buffer); buffer.removeAll(keepingCapacity: true) }
            } else if byte >= 0x80 { buffer.removeAll(keepingCapacity: true) }
            else if !buffer.isEmpty {
                buffer.append(byte)
                if buffer.count > 65536 { buffer.removeAll(keepingCapacity: true) }
            }
        }
        return messages
    }
}

public struct PianoVoice: Identifiable, Sendable {
    public let id: String
    public let bankLSB: Int
    public let program: Int // MIDI wire value (zero based)
    public let group: String
    public var value: [UInt8] { SmartPianist.encodeInteger((108 << 16) | (bankLSB << 8) | program, count: 4) }
    public var panelIndex: Int { Self.all.firstIndex(where:{$0.id == id})! }
    public var panelValue: [UInt8] { SmartPianist.encodeInteger(panelIndex,count:2) }
    public static let all: [PianoVoice] = [
        .init(id:"Grand Piano",bankLSB:0,program:0,group:"Piano"),
        .init(id:"Live Grand",bankLSB:2,program:1,group:"Piano"),
        .init(id:"Ballad Grand",bankLSB:3,program:0,group:"Piano"),
        .init(id:"Bright Grand",bankLSB:0,program:1,group:"Piano"),
        .init(id:"Stage E.Piano",bankLSB:0,program:4,group:"E.Piano"),
        .init(id:"DX E.Piano",bankLSB:0,program:5,group:"E.Piano"),
        .init(id:"Vintage E.Piano",bankLSB:1,program:4,group:"E.Piano"),
        .init(id:"Synth Piano",bankLSB:0,program:88,group:"E.Piano"),
        .init(id:"Jazz Organ",bankLSB:0,program:16,group:"Organ"),
        .init(id:"Rock Organ",bankLSB:0,program:18,group:"Organ"),
        .init(id:"Organ Principal",bankLSB:1,program:19,group:"Organ"),
        .init(id:"Organ Tutti",bankLSB:0,program:19,group:"Organ"),
        .init(id:"Harpsichord 8′",bankLSB:0,program:6,group:"Keys"),
        .init(id:"Harpsi.8′+4′",bankLSB:1,program:6,group:"Keys"),
        .init(id:"E.Clavichord",bankLSB:0,program:7,group:"Keys"),
        .init(id:"Vibraphone",bankLSB:0,program:11,group:"Keys"),
        .init(id:"Strings",bankLSB:0,program:48,group:"Strings"),
        .init(id:"Slow Strings",bankLSB:0,program:49,group:"Strings"),
        .init(id:"Choir",bankLSB:0,program:52,group:"Strings"),
        .init(id:"Synth Pad",bankLSB:0,program:89,group:"Strings"),
        .init(id:"Acoustic Bass",bankLSB:0,program:32,group:"Bass"),
        .init(id:"Electric Bass",bankLSB:0,program:33,group:"Bass"),
        .init(id:"Bass & Cymbal",bankLSB:1,program:32,group:"Bass"),
        .init(id:"Fretless Bass",bankLSB:0,program:35,group:"Bass")
    ]
}

public struct ReverbPreset: Identifiable, Sendable {
    public let id: String
    public let msb: Int
    public let lsb: Int
    public var value: [UInt8] { SmartPianist.encodeInteger((msb << 8) | lsb, count: 3) }
    public static let all: [ReverbPreset] = [
        .init(id:"Off",msb:0,lsb:0), .init(id:"Recital Hall",msb:1,lsb:24),
        .init(id:"Concert Hall",msb:1,lsb:4), .init(id:"Chamber",msb:2,lsb:24),
        .init(id:"Club",msb:3,lsb:24)
    ]
}
