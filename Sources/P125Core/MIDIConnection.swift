import Foundation
import CoreMIDI

public struct MIDIEndpoint: Identifiable, Equatable {
    public let id: Int32
    public let ref: MIDIEndpointRef
    public let name: String
    public let manufacturer: String
}

/// All public calls and callbacks run on the main thread. CoreMIDI's receive
/// callback copies packet bytes before handing them to the main queue.
public final class MIDIConnection {
    public var onMessage: (([UInt8]) -> Void)?
    public var onDevicesChanged: (() -> Void)?
    public var onDisconnect: (() -> Void)?
    public var onError: ((String) -> Void)?
    public private(set) var destinations: [MIDIEndpoint] = []
    public private(set) var selected: MIDIEndpoint?
    public private(set) var hasInput = false
    public private(set) var initializationError: String?
    private var client = MIDIClientRef()
    private var input = MIDIPortRef()
    private var output = MIDIPortRef()
    private var source = MIDIEndpointRef()
    private var framer = SysExFramer()

    public init() {
        let status = MIDIClientCreateWithBlock("P-125 Control" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        guard status == noErr else { initializationError = "CoreMIDI could not start (\(status))."; return }
        let inputStatus = MIDIInputPortCreateWithBlock(client, "P-125 replies" as CFString, &input) { [weak self] packets, _ in
            var data: [UInt8] = []
            var packet = UnsafeRawPointer(packets).advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \MIDIPacketList.packet)!).assumingMemoryBound(to: MIDIPacket.self)
            for _ in 0..<packets.pointee.numPackets {
                let count = Int(packet.pointee.length)
                let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data)!
                let bytes = UnsafeRawPointer(packet).advanced(by: dataOffset).assumingMemoryBound(to: UInt8.self)
                data.append(contentsOf: UnsafeBufferPointer(start: bytes, count: count))
                packet = UnsafePointer(MIDIPacketNext(packet))
            }
            let copied = data
            DispatchQueue.main.async {
                guard let self else { return }
                for message in self.framer.consume(copied) { self.onMessage?(message) }
            }
        }
        let outputStatus = MIDIOutputPortCreate(client, "P-125 commands" as CFString, &output)
        if inputStatus != noErr || outputStatus != noErr { initializationError = "MIDI port error (\(inputStatus), \(outputStatus))." }
        refresh()
    }

    public func refresh() {
        destinations = (0..<MIDIGetNumberOfDestinations()).compactMap { i in
            let endpoint = MIDIGetDestination(i)
            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
            let name = Self.string(endpoint, kMIDIPropertyDisplayName)
            let manufacturer = Self.string(endpoint, kMIDIPropertyManufacturer)
            // Do not discover unrelated keyboards or expose them as P-125 controls.
            guard manufacturer.localizedCaseInsensitiveContains("Yamaha") || name.localizedCaseInsensitiveContains("P-125") else { return nil }
            return MIDIEndpoint(id: uniqueID, ref: endpoint, name: name, manufacturer: manufacturer)
        }
        if let selected, !destinations.contains(where: { $0.id == selected.id && $0.ref == selected.ref }) {
            disconnect(); onDisconnect?()
        }
        onDevicesChanged?()
    }

    public func connect(to endpoint: MIDIEndpoint) throws {
        disconnect()
        guard initializationError == nil, destinations.contains(endpoint) else { throw MIDIError.message(initializationError ?? "MIDI device is no longer available.") }
        var destinationEntity = MIDIEntityRef()
        MIDIEndpointGetEntity(endpoint.ref, &destinationEntity)
        let matchingSource = (0..<MIDIGetNumberOfSources()).map(MIDIGetSource).first { candidate in
            var entity = MIDIEntityRef()
            MIDIEndpointGetEntity(candidate, &entity)
            return destinationEntity != 0 && entity == destinationEntity
        }
        guard let matchingSource else { throw MIDIError.message("The piano has no matching MIDI input. Reconnect the USB cable.") }
        let status = MIDIPortConnectSource(input, matchingSource, nil)
        guard status == noErr else { throw MIDIError.message("Could not open piano input (\(status)).") }
        source = matchingSource; selected = endpoint; hasInput = true
        framer = SysExFramer()
    }

    public func disconnect() {
        if source != 0 { MIDIPortDisconnectSource(input, source) }
        source = 0; selected = nil; hasInput = false; framer = SysExFramer()
    }

    public func send(_ bytes: [UInt8]) throws {
        guard let selected, output != 0 else { throw MIDIError.message("Connect the piano first.") }
        guard !bytes.isEmpty, bytes.count <= 1024 else { throw MIDIError.message("Invalid MIDI message size.") }
        let capacity = max(MemoryLayout<MIDIPacketList>.size, bytes.count + 64)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: MemoryLayout<MIDIPacketList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let packet = MIDIPacketListInit(list)
        bytes.withUnsafeBufferPointer { _ = MIDIPacketListAdd(list, capacity, packet, 0, bytes.count, $0.baseAddress!) }
        let status = MIDISend(output, selected.ref, list)
        guard status == noErr else { throw MIDIError.message("The piano did not accept the MIDI transfer (\(status)).") }
    }

    deinit {
        if source != 0 { MIDIPortDisconnectSource(input, source) }
        if input != 0 { MIDIPortDispose(input) }
        if output != 0 { MIDIPortDispose(output) }
        if client != 0 { MIDIClientDispose(client) }
    }

    private static func string(_ object: MIDIObjectRef, _ key: CFString) -> String {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, key, &value) == noErr else { return "" }
        return value?.takeRetainedValue() as String? ?? ""
    }
}

public enum MIDIError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
