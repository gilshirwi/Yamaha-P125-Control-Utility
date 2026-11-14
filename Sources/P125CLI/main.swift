import Foundation
import P125Core

func pump(_ seconds: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }
let connection = MIDIConnection()
if let error = connection.initializationError { fputs("\(error)\n", stderr); exit(1) }
guard let piano = connection.destinations.first(where: { $0.name.contains("Digital Piano") || $0.name.contains("P-125") }) else {
    fputs("No Yamaha piano found.\n", stderr); exit(1)
}
var values: [ParameterKey: PropertyReply] = [:]
var log: [String] = []
connection.onMessage = { bytes in
    let hex = bytes.map { String(format:"%02X",$0) }.joined(separator:" ")
    log.append("RX \(hex)")
    if let reply = SmartPianist.parse(bytes) { values[reply.key] = reply }
}
func request(_ key: ParameterKey) throws {
    try connection.send(SmartPianist.get(key)); pump(0.09)
}
func fresh(_ key: ParameterKey) throws -> PropertyReply {
    values.removeValue(forKey: key)
    try request(key)
    let deadline = Date(timeIntervalSinceNow: 1.5)
    while values[key] == nil && Date() < deadline { pump(0.02) }
    guard let value = values[key] else { throw MIDIError.message("No reply for \(key.property), index \(key.index).") }
    return value
}
do {
    try connection.connect(to:piano)
    let identity = try fresh(ParameterKey(.model))
    guard identity.string == "P-125" else { throw MIDIError.message("Expected P-125; received \(identity.string).") }
    print("Connected to Yamaha \(identity.string) via \(piano.name)")
    if CommandLine.arguments.contains("--verify-panel-index") {
        for index: UInt8 in [0,1,2] {
            let voice = try fresh(ParameterKey(.panelVoice,index))
            print("Panel voice [\(index)]: \(voice.integer)")
        }
        let key = ParameterKey(.panelVoice)
        let original = try fresh(key)
        let testIndex = original.integer == 4 ? 0 : 4
        let command = SmartPianist.set(key,value:SmartPianist.encodeInteger(testIndex,count:2))!
        let restore = SmartPianist.set(key,value:original.value)!
        defer { try? connection.send(restore); pump(0.15) }
        try connection.send(command); pump(0.25)
        let changed = try fresh(key)
        try connection.send(restore); pump(0.25)
        let restored = try fresh(key)
        print("Panel voice: \(original.integer) → \(changed.integer) → \(restored.integer)")
        print(log.joined(separator:"\n"))
        guard changed.integer == testIndex, restored.value == original.value else { throw MIDIError.message("Voice selection roundtrip failed") }
        print("PASS: P-125 keyboard voice changed and restored, confirmed by fresh hardware reads.")
        connection.disconnect(); exit(0)
    }
    if CommandLine.arguments.contains("--verify-panel-voice") {
        let key = ParameterKey(.voicePreset)
        for id in [4,0] {
            let value = [UInt8(0)] + Array(String(id).utf8)
            let command = SmartPianist.set(key,value:value)!
            print("TX panel voice \(id): " + command.map { String(format:"%02X",$0) }.joined(separator:" "))
            try connection.send(command); pump(0.3)
            try request(key); pump(0.2)
        }
        print(log.joined(separator:"\n"))
        connection.disconnect(); exit(0)
    }
    if CommandLine.arguments.contains("--verify-voice") {
        let key = ParameterKey(.voice)
        for (id,value) in [("GM Grand",SmartPianist.encodeInteger(0,count:4)),("GM E.Piano",SmartPianist.encodeInteger(4,count:4)),("Grand Piano",PianoVoice.all[0].value)] {
            let command = SmartPianist.set(key,value:value)!
            print("TX \(id): " + command.map { String(format:"%02X",$0) }.joined(separator:" "))
            try connection.send(command); pump(0.3)
            try request(key); pump(0.2)
            try request(ParameterKey(.voicePreset)); pump(0.2)
        }
        print(log.joined(separator:"\n"))
        connection.disconnect(); exit(0)
    }
    if CommandLine.arguments.contains("--mixer-state") {
        for index: UInt8 in [0,1,2,0x50] {
            let value = try fresh(ParameterKey(.volume,index))
            print("Volume [\(index)]: \(value.integer)")
        }
        connection.disconnect(); exit(0)
    }
    if CommandLine.arguments.contains("--verify-reset") {
        for (key,testValue) in [(ParameterKey(.volume),99),(ParameterKey(.volume,0x50),63),(ParameterKey(.pan),63),(ParameterKey(.reverbSend),10),(ParameterKey(.splitPoint),107)] {
            let original = try fresh(key)
            guard let change = SmartPianist.set(key,value:[UInt8(testValue)]),
                  let restore = SmartPianist.set(key,value:original.value) else { throw MIDIError.message("Invalid reset test value") }
            defer { try? connection.send(restore); pump(0.15) }
            try connection.send(change); pump(0.2)
            let changed = try fresh(key)
            try connection.send(SmartPianist.reset(key)); pump(0.2)
            let reset = try fresh(key)
            try connection.send(restore); pump(0.2)
            let restored = try fresh(key)
            print("\(key.property) [\(key.index)]: original \(original.integer), test \(changed.integer), factory default \(reset.integer), restored \(restored.integer)")
            guard changed.integer == testValue, restored.value == original.value else { throw MIDIError.message("Reset test or restoration failed") }
        }
        print(log.joined(separator:"\n"))
        connection.disconnect(); exit(0)
    }
    if CommandLine.arguments.contains("--verify-octave") {
        let key = ParameterKey(.octave)
        let original = try fresh(key)
        let testValue = original.integer == 65 ? 64 : 65
        guard let change = SmartPianist.set(key,value:[UInt8(testValue)]),
              let restore = SmartPianist.set(key,value:original.value) else { throw MIDIError.message("Invalid octave value") }
        defer { try? connection.send(restore); pump(0.15) }
        print("TX " + change.map { String(format:"%02X",$0) }.joined(separator:" "))
        try connection.send(change); pump(0.3)
        let readback = try fresh(key)
        try connection.send(restore); pump(0.2)
        let restored = try fresh(key)
        print("Octave request: \(testValue-64), Get readback: \(readback.integer-64), restored Get: \(restored.integer-64)")
        print(log.joined(separator:"\n"))
        connection.disconnect()
        exit(0)
    }
    if CommandLine.arguments.contains("--transpose-state") {
        for index: UInt8 in [0,1,2] {
            do {
                let value = try fresh(ParameterKey(.transpose,index))
                print("Transpose index \(index): \(value.value), semitones=\(value.integer-64)")
            } catch { print("Transpose index \(index): no reply") }
        }
        print(log.joined(separator:"\n"))
        connection.disconnect()
        exit(0)
    }
    if CommandLine.arguments.contains("--verify-keyboard-transpose") {
        let key = P125Parameters.keyboardTranspose
        let original = try fresh(key)
        let songOriginal = try fresh(P125Parameters.songTranspose)
        let testValue = original.integer == 66 ? 64 : 66
        guard let change = SmartPianist.set(key,value:[UInt8(testValue)]),
              let restore = SmartPianist.set(key,value:original.value) else { throw MIDIError.message("Invalid transpose value") }
        // The restore remains armed even if any of the checks throw.
        defer { try? connection.send(restore); pump(0.15) }
        print("TX " + change.map { String(format:"%02X",$0) }.joined(separator:" "))
        try connection.send(change); pump(0.2)
        let changed = try fresh(key)
        let songAfter = try fresh(P125Parameters.songTranspose)
        try connection.send(restore); pump(0.2)
        let restored = try fresh(key)
        print("Keyboard transpose: \(original.integer-64) → \(changed.integer-64) → \(restored.integer-64)")
        print("Song transpose: \(songOriginal.integer-64) → \(songAfter.integer-64)")
        print(log.joined(separator:"\n"))
        guard changed.integer == testValue, restored.value == original.value,
              songAfter.value == songOriginal.value else { throw MIDIError.message("Keyboard transpose verification failed; original keyboard setting restoration attempted.") }
        print("PASS: keyboard transpose changed and restored, song transpose unchanged; all confirmed by fresh hardware reads.")
        connection.disconnect()
        exit(0)
    }
    try request(ParameterKey(.firmware))
    for ch: UInt8 in [0,1,2] {
        for prop: PianoProperty in [.volume,.pan,.reverbSend,.octave,.panelVoice,.active] { try request(ParameterKey(prop,ch)) }
    }
    for ch: UInt8 in [0x41,0x44,0x50,0x51] { try request(ParameterKey(.volume,ch)) }
    for key in [ParameterKey(.reverbType),P125Parameters.keyboardTranspose,ParameterKey(.splitPoint),ParameterKey(.masterTune),ParameterKey(.touch)] { try request(key) }
    pump(0.8)
    let requested = [UInt8(0),1,2].flatMap { ch in
        [PianoProperty.volume,.pan,.reverbSend,.octave,.panelVoice,.active].map { ParameterKey($0,ch) }
    } + [ParameterKey(.touch)]
    for key in requested where values[key] == nil { try request(key); pump(0.2) }
    let snapshot: [[String:Any]] = values.values.sorted { ($0.key.property.rawValue, $0.key.index) < ($1.key.property.rawValue,$1.key.index) }.map { reply in
        ["property":String(describing:reply.key.property),"index":Int(reply.key.index),"value":reply.value.map(Int.init),"integer":reply.integer,"text":reply.string]
    }
    let data = try JSONSerialization.data(withJSONObject:snapshot,options:[.prettyPrinted,.sortedKeys])
    print(String(decoding:data,as:UTF8.self))
    if let arg = CommandLine.arguments.firstIndex(of:"--snapshot"), CommandLine.arguments.count > arg+1 {
        try data.write(to:URL(fileURLWithPath:CommandLine.arguments[arg+1]))
    }
    if CommandLine.arguments.contains("--roundtrip") {
        let key = ParameterKey(.volume)
        let original = try fresh(key)
        let testValue = original.integer == 100 ? 99 : (original.integer == 0 ? 1 : original.integer - 1)
        guard let set = SmartPianist.set(key,value:[UInt8(testValue)]), let restore = SmartPianist.set(key,value:original.value) else { throw MIDIError.message("Invalid roundtrip value.") }
        // Always attempt restoration, including on a failed verification.
        defer { try? connection.send(restore); pump(0.1) }
        try connection.send(set); pump(0.15)
        let changed = try fresh(key)
        try connection.send(restore); pump(0.15)
        let restored = try fresh(key)
        guard changed.integer == testValue, restored.value == original.value else { throw MIDIError.message("Hardware roundtrip failed. Original value restoration was attempted.") }
        print("PASS: Main volume \(original.integer) → \(changed.integer) → \(restored.integer), confirmed by fresh hardware reads.")
    }
    if CommandLine.arguments.contains("--verify-controls") {
        let controls: [(ParameterKey,[UInt8])] = [
            (ParameterKey(.pan),[63]), (ParameterKey(.reverbSend),[10]),
            (ParameterKey(.reverbType),ReverbPreset.all.first(where:{$0.id == "Concert Hall"})!.value),
            (P125Parameters.keyboardTranspose,[65])
        ]
        for (key,target) in controls {
            let original = try fresh(key)
            guard let set = SmartPianist.set(key,value:target), let restore = SmartPianist.set(key,value:original.value) else { throw MIDIError.message("Invalid test message") }
            defer { try? connection.send(restore); pump(0.15) }
            try connection.send(set); pump(0.2)
            let changed = try fresh(key)
            try connection.send(restore); pump(0.2)
            let restored = try fresh(key)
            guard changed.value == target, restored.value == original.value else { throw MIDIError.message("Roundtrip failed for \(key.property). Original value restoration attempted.") }
            print("PASS: \(key.property) \(original.value) → \(changed.value) → \(restored.value), fresh hardware reads.")
        }
    }
    if let pathIndex = CommandLine.arguments.firstIndex(of:"--log"), CommandLine.arguments.count > pathIndex + 1 {
        try log.joined(separator:"\n").write(toFile:CommandLine.arguments[pathIndex+1],atomically:true,encoding:.utf8)
    }
    connection.disconnect()
} catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
