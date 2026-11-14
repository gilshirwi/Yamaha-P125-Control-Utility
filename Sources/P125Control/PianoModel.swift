import Foundation
import SwiftUI
import P125Core

struct SavedSetup: Identifiable, Codable {
    struct Entry: Codable { let key: ParameterKey; let value: [UInt8] }
    let id: UUID
    let name: String
    let entries: [Entry]
    let mutedVolumes: [UInt8:Int]?
}

struct ActivityEntry: Identifiable {
    let id = UUID()
    let time = Date()
    let message: String
}

final class PianoModel: ObservableObject {
    @Published var devices: [MIDIEndpoint] = []
    @Published var selectedID: Int32 = 0
    @Published private(set) var verified = false
    @Published private(set) var connecting = false
    @Published private(set) var loading = false
    @Published private(set) var modelName = "P-125"
    @Published private(set) var firmware = ""
    @Published private(set) var values: [ParameterKey: [UInt8]] = [:]
    @Published private(set) var desired: [ParameterKey: [UInt8]] = [:]
    @Published private(set) var mutedVolumes: [UInt8:Int] = [:]
    @Published private(set) var appliedOctaves: [UInt8:Int] = [:]
    @Published private(set) var activity: [ActivityEntry] = []
    @Published private(set) var status = "Looking for your piano"
    @Published var error: String?
    @Published var setups: [SavedSetup] = []
    @Published var showSave = false
    @Published var setupName = ""
    private let midi = MIDIConnection()
    private var original: [ParameterKey: [UInt8]] = [:]
    private var commands: [[UInt8]] = []
    private var queuedWrites: [ParameterKey: [UInt8]] = [:]
    private var pendingSince: [ParameterKey: Date] = [:]
    private var writer: Timer?
    private var heartbeat: Timer?
    private var lastReply = Date.distantPast
    private var generation = UUID()
    private var snapshotting = false
    private var muteRecovery: [UInt8:Int] = [:]
    private var inFlightValues: [ParameterKey:[UInt8]] = [:]
    private var awaitingKeyboardTranspose = false
    private var retriedKeyboardTranspose = false
    private static let transposeReadError = "The piano did not report keyboard transpose. Press ⌘R to read it again."
    var canSave: Bool { verified && !loading && desired.isEmpty }

    static let mixerChannels: [UInt8] = [0,1,2]
    private static let volumeChannels: Set<UInt8> = [0,1,2,0x50]
    static let keys: [ParameterKey] = [P125Parameters.keyboardTranspose] + mixerChannels.flatMap { channel in
            [PianoProperty.volume,.pan,.reverbSend,.octave,.panelVoice,.active].map { ParameterKey($0,channel) }
        } + [ParameterKey(.volume,0x41),ParameterKey(.volume,0x44),ParameterKey(.volume,0x50),ParameterKey(.volume,0x51),
             ParameterKey(.reverbType),ParameterKey(.splitPoint),ParameterKey(.masterTune),ParameterKey(.touch)]

    init() {
        if let data = UserDefaults.standard.data(forKey:"savedSetups"), let stored = try? JSONDecoder().decode([SavedSetup].self,from:data) { setups = stored }
        midi.onMessage = { [weak self] in self?.receive($0) }
        midi.onDevicesChanged = { [weak self] in self?.updateDevices() }
        midi.onDisconnect = { [weak self] in self?.disconnected("USB disconnected") }
        devices = midi.destinations
        if let problem = midi.initializationError { status = problem; error = problem }
        writer = Timer.scheduledTimer(withTimeInterval:0.065,repeats:true) { [weak self] _ in self?.tick() }
        heartbeat = Timer.scheduledTimer(withTimeInterval:2.5,repeats:true) { [weak self] _ in self?.checkConnection() }
        DispatchQueue.main.async { [weak self] in self?.autoConnect() }
    }

    func updateDevices() {
        devices = midi.destinations
        if midi.selected == nil && !connecting { autoConnect() }
    }

    func autoConnect() {
        guard midi.selected == nil, !connecting else { return }
        let savedID = Int32(UserDefaults.standard.integer(forKey:"pianoEndpoint"))
        if let candidate = devices.first(where:{ $0.id == savedID }) ?? devices.first(where:{ $0.name.contains("Digital Piano") || $0.name.contains("P-125") }) {
            selectedID = candidate.id; connect()
        } else { status = "Connect your P-125 with a USB cable" }
    }

    func connect() {
        guard let endpoint = devices.first(where:{ $0.id == selectedID }) else { return }
        disconnected("Connecting…")
        do {
            try midi.connect(to:endpoint)
            connecting = true; status = "Identifying piano…"
            try midi.send(SmartPianist.get(ParameterKey(.model)))
            let token = generation
            DispatchQueue.main.asyncAfter(deadline:.now()+3) { [weak self] in
                guard let self, self.generation == token, !self.verified else { return }
                self.error = "The MIDI port opened, but a P-125 did not answer. Check the USB cable and close other piano-control apps, then reconnect."
                self.disconnected("Piano did not answer")
            }
        } catch { fail(error.localizedDescription); midi.disconnect() }
    }

    func disconnected(_ reason: String) {
        generation = UUID(); connecting = false; verified = false; loading = false
        commands.removeAll(); queuedWrites.removeAll(); desired.removeAll(); pendingSince.removeAll()
        values.removeAll(); original.removeAll(); snapshotting = false
        mutedVolumes.removeAll(); muteRecovery.removeAll()
        appliedOctaves.removeAll(); inFlightValues.removeAll()
        awaitingKeyboardTranspose = false; retriedKeyboardTranspose = false
        firmware = ""; status = reason; midi.disconnect()
        addLog(reason)
    }

    func refresh() {
        if verified {
            if !loading { readCurrentSettings() }
        } else {
            midi.refresh()
            if !connecting { connect() }
        }
    }

    private func readCurrentSettings() {
        loading = true
        awaitingKeyboardTranspose = true
        retriedKeyboardTranspose = false
        commands += Self.keys.map(SmartPianist.get)
        status = "Reading piano settings…"
    }

    private func finishReadback() {
        if awaitingKeyboardTranspose && !retriedKeyboardTranspose {
            retriedKeyboardTranspose = true
            commands.append(SmartPianist.get(P125Parameters.keyboardTranspose))
            return
        }
        snapshotting = false
        loading = false
        if awaitingKeyboardTranspose {
            values.removeValue(forKey:P125Parameters.keyboardTranspose)
            fail(Self.transposeReadError)
        } else if desired.isEmpty {
            status = "Synced with your piano"
        }
    }

    private func receive(_ bytes: [UInt8]) {
        guard let reply = SmartPianist.parse(bytes), midi.selected != nil else { return }
        if reply.key.property == .model {
            guard reply.string == "P-125" else { fail("This device identified itself as \(reply.string). This utility supports the P-125."); disconnected("Unsupported piano"); return }
            lastReply = Date()
            guard !verified else { return }
            verified = true; connecting = false; error = nil; modelName = reply.string
            UserDefaults.standard.set(Int(selectedID),forKey:"pianoEndpoint")
            loadMuteState()
            addLog("Yamaha P-125 identified. Two-way USB MIDI is ready.")
            snapshotting = true
            readCurrentSettings()
            commands.append(SmartPianist.get(ParameterKey(.firmware)))
            commands += [PianoProperty.volume,.pan,.reverbSend,.active,.panelVoice,.reverbType,.octave,.transpose,.splitPoint,.masterTune,.touch].map(SmartPianist.subscribe)
            status = "Reading piano settings…"
            return
        }
        guard verified else { return }
        lastReply = Date()
        if reply.key.property == .firmware { firmware = reply.string; return }
        guard Self.keys.contains(reply.key), valid(reply.key,reply.value,forWriting:false) else { return }
        let sentValue = reply.isAcknowledgement ? inFlightValues.removeValue(forKey:reply.key) : nil
        if sentValue != nil { pendingSince.removeValue(forKey:reply.key) }
        if reply.responseStatus != 0 {
            if sentValue != nil && queuedWrites[reply.key] == nil {
                desired.removeValue(forKey:reply.key)
                fail("The piano rejected \(reply.key.property) (status \(reply.responseStatus)).")
            }
            return
        }
        var effectiveValue = reply.value
        if reply.key.property == .octave {
            // P-125 firmware 1.03 reports 0x40 even after accepting a different
            // octave. Its Set acknowledgement confirms the command, but its
            // payload and subsequent Get are not the applied octave value.
            if let sent = sentValue {
                appliedOctaves[reply.key.index] = SmartPianist.decodeInteger(sent)
                effectiveValue = sent
            } else if let applied = appliedOctaves[reply.key.index] {
                effectiveValue = SmartPianist.encodeInteger(applied,count:1)
            }
        }
        if reply.key == P125Parameters.keyboardTranspose && !reply.isAcknowledgement {
            awaitingKeyboardTranspose = false
            if error == Self.transposeReadError { error = nil }
        }
        values[reply.key] = effectiveValue
        if snapshotting && original[reply.key] == nil && reply.key.property != .octave { original[reply.key] = effectiveValue }
        if let wanted = desired[reply.key], queuedWrites[reply.key] == nil, let sent = sentValue, wanted == sent {
            desired.removeValue(forKey:reply.key); pendingSince.removeValue(forKey:reply.key)
            addLog("\(reply.key.property == .octave ? "Accepted request" : "Confirmed") \(reply.key.property) [\(reply.key.index)] = \(SmartPianist.decodeInteger(effectiveValue))")
        }
        reconcileMute(reply.key)
        if !loading && commands.isEmpty && desired.isEmpty && !awaitingKeyboardTranspose { status = "Synced with your piano" }
    }

    private func tick() {
        guard verified else { return }
        if let entry = queuedWrites.filter({ inFlightValues[$0.key] == nil }).sorted(by:{ ($0.key.property.rawValue,$0.key.index) < ($1.key.property.rawValue,$1.key.index) }).first {
            queuedWrites.removeValue(forKey:entry.key)
            guard let message = SmartPianist.set(entry.key,value:entry.value) else { return }
            do {
                inFlightValues[entry.key] = entry.value
                try midi.send(message); pendingSince[entry.key] = Date()
            } catch { disconnected("MIDI transfer failed"); fail(error.localizedDescription) }
        } else if !commands.isEmpty {
            let message = commands.removeFirst()
            do { try midi.send(message) } catch { fail(error.localizedDescription) }
        } else if loading {
            // Let the last MIDI response reach the main queue before checking
            // whether the initial or manually requested read has completed.
            finishReadback()
        }
        for (key,since) in pendingSince where Date().timeIntervalSince(since) > 2.5 {
            pendingSince.removeValue(forKey:key)
            inFlightValues.removeValue(forKey:key)
            guard queuedWrites[key] == nil else { continue }
            desired.removeValue(forKey:key)
            if key.property == .volume, values[key] == [0], let level = muteRecovery[key.index] {
                mutedVolumes[key.index] = level
            } else { reconcileMute(key) }
            fail("The piano did not confirm \(key.property). Its last reported value is shown.")
            commands.append(SmartPianist.get(key))
        }
    }

    private func checkConnection() {
        guard verified else { return }
        if Date().timeIntervalSince(lastReply) > 12 { disconnected("Piano stopped responding — reconnect to continue"); return }
        guard !loading, commands.isEmpty else { return }
        commands.append(SmartPianist.get(ParameterKey(.model)))
        // Subscriptions provide live changes; slow polling also covers panel
        // changes on firmware that does not emit a subscribed event.
        commands += Self.keys.map(SmartPianist.get)
    }

    func supported(_ key: ParameterKey) -> Bool { verified && !loading && values[key] != nil }
    func integer(_ key: ParameterKey) -> Int? { (desired[key] ?? values[key]).map(SmartPianist.decodeInteger) }
    func bytes(_ key: ParameterKey) -> [UInt8]? { desired[key] ?? values[key] }
    func octaveSelection(_ channel: UInt8) -> Int {
        if let wanted = desired[ParameterKey(.octave,channel)] { return SmartPianist.decodeInteger(wanted) }
        return appliedOctaves[channel] ?? -1
    }

    func isMuted(_ channel: UInt8) -> Bool { mutedVolumes[channel] != nil }
    func mixerVolume(_ channel: UInt8) -> Int? { mutedVolumes[channel] ?? integer(ParameterKey(.volume,channel)) }

    func toggleMute(_ channel: UInt8) {
        let key = ParameterKey(.volume,channel)
        guard Self.volumeChannels.contains(channel), supported(key) else { return }
        if let previous = mutedVolumes.removeValue(forKey:channel) {
            // Keep recovery data until a nonzero restore is acknowledged.
            // A zero-volume channel should remain at zero when unmuted.
            if previous == 0 { muteRecovery.removeValue(forKey:channel); persistMuteState() }
            set(key,integer:previous)
        } else if let current = integer(key) {
            mutedVolumes[channel] = current; muteRecovery[channel] = current
            persistMuteState()
            set(key,integer:0)
        }
    }

    func setMixerVolume(_ channel: UInt8, integer: Int) {
        guard Self.volumeChannels.contains(channel), (0...127).contains(integer), supported(ParameterKey(.volume,channel)) else { return }
        if isMuted(channel) {
            mutedVolumes[channel] = integer; muteRecovery[channel] = integer
            persistMuteState()
        } else { set(ParameterKey(.volume,channel),integer:integer) }
    }

    func resetToDefault(_ key: ParameterKey) {
        guard supported(key) else { return }
        switch key.property {
        case .octave, .transpose:
            set(key,integer:64)
        case .masterTune:
            set(key,integer:1024,count:2)
        case .splitPoint:
            // Yamaha names this F#2; scientific pitch notation is F#3.
            set(key,integer:54)
        case .volume where isMuted(key.index):
            setMixerVolume(key.index,integer:key.index == 0x50 ? 64 : 100)
        case .volume, .pan, .reverbSend:
            // Let the piano choose its voice-dependent default, particularly
            // reverb depth, instead of substituting a guessed fixed value.
            queuedWrites.removeValue(forKey:key); desired.removeValue(forKey:key)
            if key.property == .volume { muteRecovery.removeValue(forKey:key.index); persistMuteState() }
            commands.insert(contentsOf:[SmartPianist.reset(key),SmartPianist.get(key)],at:0)
            status = "Resetting to piano default…"
        default: break
        }
    }

    private var muteStorageKey: String { "muteRestoreVolumes.\(selectedID)" }
    private func persistMuteState() {
        if let data = try? JSONEncoder().encode(muteRecovery) { UserDefaults.standard.set(data,forKey:muteStorageKey) }
    }
    private func loadMuteState() {
        let data = UserDefaults.standard.data(forKey:muteStorageKey)
        let stored = data.flatMap { try? JSONDecoder().decode([UInt8:Int].self,from:$0) } ?? [:]
        muteRecovery = stored.filter { Self.volumeChannels.contains($0.key) && (0...127).contains($0.value) }
        mutedVolumes = muteRecovery
    }
    private func reconcileMute(_ key: ParameterKey) {
        guard key.property == .volume, desired[key] == nil, queuedWrites[key] == nil,
              let actual = values[key], SmartPianist.decodeInteger(actual) > 0 else { return }
        // A nonzero hardware value also detects external unmuting.
        mutedVolumes.removeValue(forKey:key.index)
        if muteRecovery.removeValue(forKey:key.index) != nil { persistMuteState() }
    }
    private func prepareMuteState(_ restored: [UInt8:Int], volumes: [ParameterKey:[UInt8]]) {
        mutedVolumes = restored.filter {
            Self.volumeChannels.contains($0.key) && (0...127).contains($0.value) &&
            supported(ParameterKey(.volume,$0.key)) && volumes[ParameterKey(.volume,$0.key)] == [0]
        }
        for (key,value) in volumes where key.property == .volume && value == [0] && mutedVolumes[key.index] == nil {
            muteRecovery.removeValue(forKey:key.index)
        }
        muteRecovery.merge(mutedVolumes) { _,new in new }; persistMuteState()
    }

    func set(_ key: ParameterKey, integer: Int, count: Int = 1) {
        guard count > 0, count <= 4, integer >= 0, integer < (1 << (count * 7)) else { return }
        // The piano quantizes tuning to 0.1 Hz: four raw units per step.
        let quantized = key.property == .masterTune ? max(4,min(2044,Int((Double(integer)/4).rounded())*4)) : integer
        set(key,value:SmartPianist.encodeInteger(quantized,count:count))
    }

    func set(_ key: ParameterKey, value: [UInt8]) {
        guard supported(key), valid(key,value,forWriting:true), let current = bytes(key), current != value || key.property == .octave else { return }
        desired[key] = value; queuedWrites[key] = value
        if key.property == .panelVoice && isMuted(key.index) {
            let volume = ParameterKey(.volume,key.index)
            desired[volume] = [0]; queuedWrites[volume] = [0]
        }
        // Snapshot no longer changes once the user begins editing.
        snapshotting = false; status = "Applying to piano…"
    }

    private func valid(_ key: ParameterKey, _ value: [UInt8], forWriting: Bool) -> Bool {
        guard !value.isEmpty, value.count <= 4, value.allSatisfy({ $0 < 128 }) else { return false }
        let number = SmartPianist.decodeInteger(value)
        switch key.property {
        case .volume,.pan,.reverbSend: return value.count == 1 && (0...127).contains(number)
        case .active: return value.count == 1 && (0...1).contains(number)
        case .octave: return value.count == 1 && (62...66).contains(number)
        case .transpose: return key == P125Parameters.keyboardTranspose && value.count == 1 && (52...76).contains(number)
        case .splitPoint: return value.count == 1 && (21...108).contains(number)
        case .masterTune: return value.count == 2 && (4...2047).contains(number)
        case .touch: return value.count == 1 && (0...4).contains(number)
        case .panelVoice: return value.count == 2 && PianoVoice.all.indices.contains(number)
        case .voice: return value.count == 4 && (!forWriting || PianoVoice.all.contains(where:{$0.value == value}))
        case .reverbType: return value.count == 3 && (!forWriting || ReverbPreset.all.contains(where:{$0.value == value}))
        default: return false
        }
    }

    func restoreOriginal() {
        prepareMuteState([:],volumes:original)
        for (key,value) in original { set(key,value:value) }
        addLog("Restoring settings captured when this session connected.")
    }

    func saveSetup() {
        let name = setupName.trimmingCharacters(in:.whitespacesAndNewlines)
        guard canSave, !name.isEmpty else { return }
        let entries = values.filter {
            valid($0.key,$0.value,forWriting:true) && ($0.key.property != .octave || appliedOctaves[$0.key.index] != nil)
        }.map { SavedSetup.Entry(key:$0.key,value:$0.value) }
        setups.append(SavedSetup(id:UUID(),name:String(name.prefix(80)),entries:entries,mutedVolumes:mutedVolumes))
        persistSetups(); showSave = false; setupName = ""; addLog("Saved setup: \(name)")
    }

    func recall(_ setup: SavedSetup) {
        var restored: [ParameterKey:[UInt8]] = [:]
        for entry in setup.entries { restored[entry.key] = entry.value }
        prepareMuteState(setup.mutedVolumes ?? [:],volumes:restored)
        for entry in setup.entries { set(entry.key,value:entry.value) }
        addLog("Recalling setup: \(setup.name)")
    }

    func deleteSetup(_ id: UUID) { setups.removeAll { $0.id == id }; persistSetups() }
    private func persistSetups() { if let data = try? JSONEncoder().encode(setups) { UserDefaults.standard.set(data,forKey:"savedSetups") } }
    private func fail(_ message: String) { error = message; status = message; addLog(message) }
    private func addLog(_ message: String) { activity.insert(ActivityEntry(message:message),at:0); if activity.count > 200 { activity.removeLast() } }
    deinit { writer?.invalidate(); heartbeat?.invalidate() }
}
