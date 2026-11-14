import SwiftUI
import P125Core

private enum Page: String, CaseIterable {
    case mixer = "Mixer", sound = "Sound & keys", setups = "Saved setups", connection = "Connection"
    var icon: String {
        switch self { case .mixer: return "slider.vertical.3"; case .sound: return "pianokeys"; case .setups: return "square.stack"; case .connection: return "cable.connector" }
    }
}
struct ControlDesk: View {
    @ObservedObject var piano: PianoModel
    @State private var page = Page.mixer
    var body: some View {
        HStack(spacing:0) {
            sidebar
            VStack(spacing:0) {
                header
                Rectangle().fill(DeskStyle.line).frame(height:1)
                ScrollView {
                    VStack(alignment:.leading,spacing:24) {
                        if let error = piano.error {
                            HStack(alignment:.top) {
                                Image(systemName:"exclamationmark.circle").foregroundStyle(.orange)
                                Text(error).font(.callout).textSelection(.enabled)
                                Spacer()
                                Button { piano.error = nil } label: { Image(systemName:"xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
                            }.padding(14).background(Color.orange.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
                        }
                        if piano.loading {
                            HStack(spacing:12) {
                                ProgressView().controlSize(.small)
                                Text("Reading current piano settings…").font(.callout)
                            }.padding(14).frame(maxWidth:.infinity,alignment:.leading).panel()
                        } else if !piano.verified {
                            HStack(spacing:16) {
                                Image(systemName:"cable.connector").font(.title2).foregroundStyle(.orange)
                                VStack(alignment:.leading,spacing:5) {
                                    Text(piano.connecting ? "Connecting to your piano…" : "Connect your P-125").font(.headline)
                                    Text("Turn on the piano and connect USB TO HOST to this Mac.").font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Try again") { piano.refresh() }
                            }.padding(20).panel()
                        }
                        switch page {
                        case .mixer: mixer
                        case .sound: sound
                        case .setups: setups
                        case .connection: connection
                        }
                    }.padding(30)
                }
                HStack {
                    Circle().fill(piano.desired.isEmpty ? (piano.verified ? DeskStyle.accent : .gray) : .orange).frame(width:5,height:5)
                    Text(piano.status).font(.system(size:10)).lineLimit(1)
                    Spacer()
                    Text(versionLabel).font(.system(size:9,design:.monospaced)).tracking(1).foregroundStyle(.tertiary)
                }.foregroundStyle(.secondary).padding(.horizontal,30).padding(.vertical,12).background(.black.opacity(0.12))
            }
        }.foregroundStyle(DeskStyle.text).background(DeskStyle.background).tint(DeskStyle.accent)
            .sheet(isPresented:$piano.showSave) { saveSheet }
    }

    private var versionLabel: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return "P-125 CONTROL"
        }
        return "P-125 CONTROL  /  \(version)"
    }

    private var sidebar: some View {
        VStack(alignment:.leading,spacing:0) {
            ControlDeskWordmark(size: 34).padding(.top, 42)
            VStack(spacing:7) {
                ForEach(Page.allCases,id:\.self) { item in
                    Button { page = item } label: {
                        HStack(spacing:11) {
                            Image(systemName:item.icon).frame(width:19)
                            Text(item.rawValue).font(.system(size:13,weight:page == item ? .semibold : .regular))
                            Spacer(minLength:0)
                        }.padding(.horizontal,12).padding(.vertical,12)
                            .foregroundStyle(page == item ? DeskStyle.accent : .secondary)
                            .background(page == item ? DeskStyle.accent.opacity(0.09) : .clear,in:RoundedRectangle(cornerRadius:9))
                    }.buttonStyle(.plain)
                }
            }.padding(.top,44)
            Spacer()
            Image(systemName:"waveform.path").font(.system(size:28,weight:.ultraLight)).foregroundStyle(DeskStyle.accent.opacity(0.5)).padding(.bottom,15)
            Text("The sound is in\nyour piano.").font(.system(size:13,weight:.light)).foregroundStyle(.secondary).lineSpacing(4)
            Text("USB · CORE MIDI").font(.system(size:9,design:.monospaced)).tracking(1).foregroundStyle(.tertiary).padding(.top,19).padding(.bottom,25)
        }.padding(.horizontal,20).frame(width:200).background(.black.opacity(0.16))
    }
    private var header: some View {
        HStack(spacing:12) {
            Text("YAMAHA").font(.system(size:10,weight:.semibold,design:.monospaced)).tracking(2).foregroundStyle(.secondary)
            Text("/").foregroundStyle(.tertiary)
            Text(piano.modelName).font(.system(size:13,weight:.medium))
            Spacer()
            ControlDeskConnectionBadge(piano: piano)
            Button { piano.refresh() } label: { Image(systemName:"arrow.clockwise") }.buttonStyle(.plain).help("Read settings from piano (⌘R)").accessibilityLabel("Refresh piano settings")
        }.padding(.horizontal,30).padding(.top,23).padding(.bottom,18)
    }
    private func title(_ eyebrow:String,_ heading:String,_ detail:String) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(eyebrow.uppercased()).font(.system(size:9,weight:.semibold,design:.monospaced)).tracking(2).foregroundStyle(DeskStyle.accent)
            Text(heading).font(.system(size:29,weight:.light))
            Text(detail).font(.system(size:12)).foregroundStyle(.secondary)
        }
    }
    private var mixer: some View {
        VStack(alignment:.leading,spacing:23) {
            HStack(alignment:.bottom) {
                title("01 / MIXER","Your piano, within reach.","Adjust the internal keyboard parts. Changes go straight to your P-125.")
                Spacer()
                Button("Save setup",systemImage:"bookmark") { piano.showSave = true }.disabled(!piano.canSave)
            }
            HStack(alignment:.top,spacing:14) {
                ChannelStrip(piano:piano,channel:0,name:"Main",caption:"PRIMARY VOICE",color:DeskStyle.accent)
                ChannelStrip(piano:piano,channel:1,name:"Layer",caption:"SECOND VOICE",color:Color(red:0.70,green:0.69,blue:0.92))
                ChannelStrip(piano:piano,channel:2,name:"Left",caption:"SPLIT VOICE",color:Color(red:0.90,green:0.74,blue:0.51))
            }
            HStack(spacing:24) {
                label("MIDI song","Playback balance").frame(width:150,alignment:.leading)
                ParameterSlider(piano:piano,key:ParameterKey(.volume,0x50),range:0...127)
                MuteButton(piano:piano,channel:0x50,name:"MIDI song")
            }.padding(20).panel()
            Text("Layer adds a second voice; Left enables a split. Controls become available after the piano reports their values.").font(.system(size:11)).foregroundStyle(.secondary)
        }
    }
    private var sound: some View {
        VStack(alignment:.leading,spacing:22) {
            title("02 / SOUND & KEYS","Find your space.","Reverb, tuning and the way the keyboard responds.")
            VStack(alignment:.leading,spacing:20) {
                Label("Reverb room",systemImage:"waveform.path").font(.system(size:16,weight:.medium))
                HStack(spacing:9) {
                    ForEach(ReverbPreset.all) { preset in
                        let selected = piano.bytes(ParameterKey(.reverbType)) == preset.value
                        Button { piano.set(ParameterKey(.reverbType),value:preset.value) } label: {
                            VStack(spacing:13) {
                                Image(systemName:preset.id == "Off" ? "speaker.slash" : "building.2").font(.system(size:21,weight:.light))
                                Text(preset.id).font(.system(size:11,weight:.medium))
                            }.frame(maxWidth:.infinity).padding(.vertical,24)
                                .foregroundStyle(selected ? DeskStyle.accent : .secondary)
                                .background(selected ? DeskStyle.accent.opacity(0.09) : .white.opacity(0.025),in:RoundedRectangle(cornerRadius:10))
                                .overlay(RoundedRectangle(cornerRadius:10).stroke(selected ? DeskStyle.accent.opacity(0.45) : DeskStyle.line))
                        }.buttonStyle(.plain).disabled(!piano.supported(ParameterKey(.reverbType)))
                    }
                }
                Text("Reverb depth is set independently for each part in the mixer.").font(.system(size:11)).foregroundStyle(.secondary)
            }.padding(22).panel()
            VStack(spacing:24) {
                HStack {
                    label("Keyboard transpose","Semitones for the keys you play").frame(width:230,alignment:.leading)
                    ParameterSlider(piano:piano,key:P125Parameters.keyboardTranspose,range:52...76,format:{ signed($0-64) })
                    Button("Reset") { piano.set(P125Parameters.keyboardTranspose,integer:64) }
                        .disabled(!piano.supported(P125Parameters.keyboardTranspose)).help("Return keyboard transpose to zero")
                }
                Divider()
                HStack {
                    label("Split point","The highest key in the Left part").frame(width:230,alignment:.leading)
                    ParameterSlider(piano:piano,key:ParameterKey(.splitPoint),range:21...108,format:noteName)
                }
                Divider()
                HStack {
                    label("Master tuning","A4 reference pitch").frame(width:230,alignment:.leading)
                    ParameterSlider(piano:piano,key:ParameterKey(.masterTune),range:4...2044,count:2,format:{ String(format:"%.1f Hz",440.0+Double($0-1024)/40.0) })
                }
            }.padding(22).panel()
        }
    }
    private var setups: some View {
        VStack(alignment:.leading,spacing:22) {
            title("03 / SAVED SETUPS","Keep a sound you love.","Save confirmed settings on this Mac and recall them on your piano.")
            HStack {
                Button("Save current setup",systemImage:"plus") { piano.showSave = true }.disabled(!piano.canSave)
                Spacer()
                Button("Restore connection settings",systemImage:"arrow.uturn.backward") { piano.restoreOriginal() }.disabled(!piano.verified)
            }
            if piano.setups.isEmpty {
                VStack(spacing:12) {
                    Image(systemName:"bookmark").font(.system(size:32,weight:.ultraLight)).foregroundStyle(DeskStyle.accent)
                    Text("Make this sound yours.").font(.system(size:20,weight:.light))
                    Text("Saved setups will appear here.").font(.system(size:12)).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity).padding(.vertical,65).panel()
            }
            ForEach(piano.setups) { setup in
                HStack {
                    Image(systemName:"pianokeys").foregroundStyle(DeskStyle.accent).padding(.trailing,9)
                    label(setup.name,"\(setup.entries.count) piano settings")
                    Spacer()
                    Button("Recall") { piano.recall(setup) }.disabled(!piano.verified)
                    Button { piano.deleteSetup(setup.id) } label: { Image(systemName:"trash") }.buttonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel("Delete \(setup.name)")
                }.padding(20).panel()
            }
        }
    }
    private var connection: some View {
        VStack(alignment:.leading,spacing:22) {
            title("04 / CONNECTION","A direct line.","Two-way communication with the instrument over USB MIDI.")
            VStack(alignment:.leading,spacing:18) {
                HStack {
                    Picker("Yamaha MIDI device",selection:$piano.selectedID) {
                        Text("Select piano").tag(Int32(0))
                        ForEach(piano.devices) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth:440)
                    Button("Reconnect") { piano.connect() }.disabled(piano.selectedID == 0)
                }
                HStack(spacing:35) {
                    label("Model",piano.verified ? piano.modelName : "—")
                    label("Firmware",piano.firmware.isEmpty ? "—" : piano.firmware)
                    label("Parameters","\(piano.values.count)")
                    label("Protocol","Yamaha SysEx")
                }
            }.padding(22).panel()
            VStack(alignment:.leading,spacing:16) {
                Text("Activity").font(.system(size:15,weight:.medium))
                ForEach(piano.activity.prefix(24)) { event in
                    HStack(alignment:.top,spacing:16) {
                        Text(event.time,style:.time).font(.system(size:10,design:.monospaced)).foregroundStyle(.tertiary).frame(width:80,alignment:.leading)
                        Text(event.message).font(.system(size:11)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }.padding(22).frame(maxWidth:.infinity,alignment:.leading).panel()
            Text("P-125 Control is an independent utility. Opening the app reads settings without changing them. Audio comes directly from your piano.").font(.system(size:11)).foregroundStyle(.secondary)
        }
    }
    private func label(_ text:String,_ detail:String) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(text).font(.system(size:13,weight:.medium))
            Text(detail).font(.system(size:11)).foregroundStyle(.secondary)
        }
    }
    private var saveSheet: some View {
        VStack(alignment:.leading,spacing:20) {
            Text("Save this setup").font(.system(size:23,weight:.light))
            Text("Store the piano’s confirmed settings on this Mac.").font(.callout).foregroundStyle(.secondary)
            TextField("Setup name",text:$piano.setupName).textFieldStyle(.roundedBorder).onSubmit { piano.saveSetup() }
            HStack {
                Button("Cancel") { piano.showSave = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { piano.saveSetup() }.keyboardShortcut(.defaultAction).disabled(!piano.canSave || piano.setupName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
        }.padding(30).frame(width:390)
    }
}

private struct ChannelStrip: View {
    @ObservedObject var piano: PianoModel
    let channel: UInt8
    let name: String
    let caption: String
    let color: Color
    private var volume: ParameterKey { ParameterKey(.volume,channel) }
    private var active: ParameterKey { ParameterKey(.active,channel) }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Text(String(format:"%02d",Int(channel)+1)).font(.system(size:10,design:.monospaced)).foregroundStyle(color)
                Spacer()
                if channel == 0 { Text("PRIMARY").font(.system(size:8,weight:.semibold)).tracking(1).foregroundStyle(color) }
                else {
                    Toggle("Enable \(name)",isOn:Binding(get:{ piano.integer(active) == 1 },set:{ piano.set(active,integer:$0 ? 1 : 0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini).disabled(!piano.supported(active))
                }
            }
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text(name).font(.system(size:25,weight:.light))
                    Text(caption).font(.system(size:8,weight:.medium,design:.monospaced)).tracking(1.2).foregroundStyle(.secondary)
                }
                Spacer(minLength:6)
                MuteButton(piano:piano,channel:channel,name:name)
            }
            VoicePicker(piano:piano,channel:channel)
            HStack(spacing:0) {
                VStack(alignment:.leading,spacing:5) {
                    Text(piano.mixerVolume(channel).map(String.init) ?? "—").font(.system(size:43,weight:.ultraLight,design:.rounded)).monospacedDigit()
                        .resetOnDoubleClick { piano.resetToDefault(volume) }
                    Text("VOLUME / 127").font(.system(size:8,design:.monospaced)).tracking(0.6).foregroundStyle(.tertiary)
                }.frame(maxWidth:.infinity,alignment:.leading)
                VolumeFader(value:Binding(get:{ Double(piano.mixerVolume(channel) ?? 0) },set:{ piano.setMixerVolume(channel,integer:Int($0.rounded())) }),enabled:piano.supported(volume),color:color,onReset:{ piano.resetToDefault(volume) })
                    .accessibilityLabel("\(name) volume")
            }.opacity(piano.isMuted(channel) ? 0.5 : 1)
            Rectangle().fill(DeskStyle.line).frame(height:1)
            VStack(alignment:.leading,spacing:8) {
                Text("PAN").font(.system(size:8,design:.monospaced)).tracking(1).foregroundStyle(.secondary)
                ParameterSlider(piano:piano,key:ParameterKey(.pan,channel),range:1...127,format:{ $0 == 64 ? "C" : ($0 < 64 ? "L\(64-$0)" : "R\($0-64)") },compact:true)
                Text("REVERB DEPTH").font(.system(size:8,design:.monospaced)).tracking(1).foregroundStyle(.secondary).padding(.top,9)
                ParameterSlider(piano:piano,key:ParameterKey(.reverbSend,channel),range:0...127,compact:true)
            }
            HStack {
                Text("OCTAVE").font(.system(size:8,design:.monospaced)).tracking(1).foregroundStyle(.secondary)
                    .resetOnDoubleClick { piano.resetToDefault(ParameterKey(.octave,channel)) }
                Spacer()
                let key = ParameterKey(.octave,channel)
                OctaveSelector(piano:piano,channel:channel,name:name)
                Button { piano.set(key,integer:64) } label: { Image(systemName:"arrow.counterclockwise").font(.system(size:10)) }
                    .buttonStyle(.plain).disabled(!piano.supported(key)).accessibilityLabel("Reset \(name) octave")
                    .help("Always send octave 0 to \(name)")
            }
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading).panel()
    }
}

private struct VoicePicker: View {
    @ObservedObject var piano: PianoModel
    let channel: UInt8
    var body: some View {
        let key = ParameterKey(.panelVoice,channel)
        let voice = PianoVoice.all.first { $0.panelIndex == piano.integer(key) }
        Picker("Voice",selection:Binding(get:{ voice?.id ?? "" },set:{ id in if let item = PianoVoice.all.first(where:{$0.id == id}) { piano.set(key,value:item.panelValue) } })) {
            if voice == nil { Text("Reading voice…").tag("") }
            ForEach(["Piano","E.Piano","Organ","Keys","Strings","Bass"],id:\.self) { group in
                Section(header:Text(group)) {
                    ForEach(PianoVoice.all.filter { $0.group == group }) { Text($0.id).tag($0.id) }
                }
            }
        }.labelsHidden().controlSize(.small).disabled(!piano.supported(key)).accessibilityLabel("Voice for part \(channel+1)")
    }
}

private struct ParameterSlider: View {
    @ObservedObject var piano: PianoModel
    let key: ParameterKey
    let range: ClosedRange<Double>
    var count = 1
    var format: (Int) -> String = { String($0) }
    var compact = false
    private var displayValue: Int? { key.property == .volume ? piano.mixerVolume(key.index) : piano.integer(key) }
    var body: some View {
        HStack(spacing:12) {
            PianoSlider(value:Binding(get:{ Double(displayValue ?? Int(range.lowerBound)) },set:{
                if key.property == .volume { piano.setMixerVolume(key.index,integer:Int($0.rounded())) }
                else { piano.set(key,integer:Int($0.rounded()),count:count) }
            }),range:range,enabled:piano.supported(key),step:key.property == .masterTune ? 4 : 1,onReset:{ piano.resetToDefault(key) })
                .frame(maxWidth:.infinity).frame(height:20)
                .accessibilityLabel("\(String(describing:key.property)), part \(key.index+1)")
            Text(displayValue.map(format) ?? "—").font(.system(size:compact ? 11 : 12,weight:.medium,design:.monospaced))
                .foregroundStyle(piano.supported(key) ? DeskStyle.text : .secondary)
                .frame(width:compact ? 31 : 76,alignment:.trailing).monospacedDigit()
                .resetOnDoubleClick { piano.resetToDefault(key) }
        }
    }
}
private struct MuteButton: View {
    @ObservedObject var piano: PianoModel
    let channel: UInt8
    let name: String
    var body: some View {
        let muted = piano.isMuted(channel)
        Button { piano.toggleMute(channel) } label: {
            Label(muted ? "Muted" : "Mute",systemImage:muted ? "speaker.slash.fill" : "speaker.wave.2")
                .font(.system(size:10,weight:.semibold)).padding(.horizontal,9).padding(.vertical,7)
                .foregroundStyle(muted ? .orange : .secondary)
                .background(muted ? Color.orange.opacity(0.15) : .white.opacity(0.04),in:RoundedRectangle(cornerRadius:7))
                .overlay(RoundedRectangle(cornerRadius:7).stroke(muted ? .orange.opacity(0.4) : DeskStyle.line))
        }.buttonStyle(.plain).disabled(!piano.supported(ParameterKey(.volume,channel)))
            .accessibilityLabel("\(muted ? "Unmute" : "Mute") \(name)")
            .help(muted ? "Restore \(name) to its previous volume" : "Mute \(name) and remember its volume")
    }
}
private struct VolumeFader: View {
    @Binding var value: Double
    let enabled: Bool
    let color: Color
    let onReset: () -> Void
    var body: some View {
        PianoSlider(value:$value,range:0...127,enabled:enabled,vertical:true,color:color,onReset:onReset)
            .frame(width:38,height:170)
    }
}

private struct OctaveSelector: View {
    @ObservedObject var piano: PianoModel
    let channel: UInt8
    let name: String
    @State private var open = false
    private var key: ParameterKey { ParameterKey(.octave,channel) }
    private var display: String {
        let selected = piano.octaveSelection(channel)
        return selected == -1 ? "—" : signed(selected-64)
    }
    var body: some View {
        HStack(spacing:8) {
            Text(display).font(.system(size:11,design:.monospaced)).frame(maxWidth:.infinity)
            Image(systemName:"chevron.up.chevron.down").font(.system(size:8,weight:.semibold))
        }.padding(.horizontal,7).padding(.vertical,4).frame(width:63)
            .background(.white.opacity(0.1),in:RoundedRectangle(cornerRadius:5))
            .contentShape(Rectangle()).opacity(piano.supported(key) ? 1 : 0.35)
            .gesture(TapGesture(count:2).exclusively(before:TapGesture()).onEnded { gesture in
                guard piano.supported(key) else { return }
                switch gesture {
                case .first: piano.resetToDefault(key)
                case .second: open = true
                }
            })
            .popover(isPresented:$open,arrowEdge:.bottom) {
                VStack(spacing:2) {
                    ForEach(62...66,id:\.self) { raw in
                        Button {
                            piano.set(key,integer:raw); open = false
                        } label: {
                            HStack {
                                Image(systemName:"checkmark").opacity(piano.octaveSelection(channel) == raw ? 1 : 0).frame(width:14)
                                Text(signed(raw-64)).frame(width:30)
                            }.font(.system(size:12)).padding(.horizontal,12).padding(.vertical,7).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(6)
            }
            .accessibilityElement(children:.ignore).accessibilityLabel("\(name) octave").accessibilityValue(display)
            .accessibilityAddTraits(.isButton).accessibilityAction { if piano.supported(key) { open = true } }
            .help("Last octave chosen in this connection. Double-click to reset to zero.")
    }
}

private extension View {
    func resetOnDoubleClick(_ action: @escaping () -> Void) -> some View {
        self.simultaneousGesture(TapGesture(count:2).onEnded {
            // Run after the native control's click/drag handlers, so a second
            // click cannot overwrite the reset with its pointer position.
            DispatchQueue.main.async(execute:action)
        }).help("Double-click to reset to default")
    }
}
private func signed(_ value:Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
private func noteName(_ note:Int) -> String {
    let names = ["C","C♯","D","D♯","E","F","F♯","G","G♯","A","A♯","B"]
    return "\(names[note%12])\(note/12-1)"
}
