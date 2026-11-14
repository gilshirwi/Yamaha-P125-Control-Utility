import XCTest
@testable import P125Core

final class ProtocolTests: XCTestCase {
    // Actual bytes returned by the connected P-125, firmware 1.03.
    private let model: [UInt8] = [0xF0,0x43,0x73,0x01,0x52,0x25,0x26,0,0,0x0F,1,0x18,1,0,1,0,0,6,0,0x50,0x2D,0x31,0x32,0x35,0xF7]
    private let volume: [UInt8] = [0xF0,0x43,0x73,0x01,0x52,0x25,0x26,0,0,0x0C,0,0,1,0,1,0,0,1,100,0xF7]

    func testHardwareIdentity() {
        let reply = SmartPianist.parse(model)
        XCTAssertEqual(reply?.string,"P-125")
        XCTAssertEqual(reply?.key,ParameterKey(.model))
    }
    func testHardwareVolume() {
        let reply = SmartPianist.parse(volume)
        XCTAssertEqual(reply?.integer,100)
        XCTAssertEqual(reply?.key,ParameterKey(.volume))
        XCTAssertEqual(reply?.isAcknowledgement,false)
    }
    func testP125PanelVoiceUsesTwoByteIndex() {
        let stage = PianoVoice.all.first { $0.id == "Stage E.Piano" }!
        XCTAssertEqual(stage.panelIndex,4)
        XCTAssertEqual(SmartPianist.set(ParameterKey(.panelVoice),value:stage.panelValue),
                       [0xF0,0x43,0x73,0x01,0x52,0x25,0x26,1,1,2,0,3,1,0,1,0,0,2,0,4,0xF7])
    }
    func testRejectedVoiceCommandIsNotSuccessfulAcknowledgement() {
        let rejected:[UInt8] = [0xF0,0x43,0x73,0x01,0x52,0x25,0x26,0,1,2,0,1,1,0,1,0,2,1,0,4,3,48,0,4,0xF7]
        XCTAssertEqual(SmartPianist.parse(rejected)?.responseStatus,257)
        XCTAssertEqual(SmartPianist.parse(volume)?.responseStatus,0)
    }
    func testKeyboardTransposeUsesKeyboardTargetRatherThanSong() {
        let command = SmartPianist.set(P125Parameters.keyboardTranspose,value:[66])
        XCTAssertEqual(command,[0xF0,0x43,0x73,0x01,0x52,0x25,0x26,1,1,0x0A,0,0,1,1,1,0,0,1,66,0xF7])
        XCTAssertNotEqual(P125Parameters.keyboardTranspose,P125Parameters.songTranspose)
    }
    func testHardwareKeyboardTransposeReply() {
        let bytes: [UInt8] = [0xF0,0x43,0x73,0x01,0x52,0x25,0x26,0,0,0x0A,0,0,1,1,1,0,0,1,64,0xF7]
        let reply = SmartPianist.parse(bytes)
        XCTAssertEqual(reply?.key,P125Parameters.keyboardTranspose)
        XCTAssertEqual(reply?.integer,64)
        XCTAssertNotEqual(reply?.key,P125Parameters.songTranspose)
    }
    func testSetAcknowledgementHasExtraStatusBytes() {
        var response = volume
        response[8] = 1
        response.insert(contentsOf:[0,0],at:16)
        XCTAssertEqual(SmartPianist.parse(response)?.integer,100)
        XCTAssertEqual(SmartPianist.parse(response)?.isAcknowledgement,true)
    }
    func testRejectsTruncationAndIncorrectLengths() {
        for length in 0..<volume.count { XCTAssertNil(SmartPianist.parse(Array(volume.prefix(length)))) }
        var invalid = volume; invalid[17] = 2
        XCTAssertNil(SmartPianist.parse(invalid))
        invalid = volume; invalid[14] = 3
        XCTAssertNil(SmartPianist.parse(invalid))
    }
    func testRejectsForeignManufacturerAndInvalidData() {
        var invalid = volume; invalid[1] = 0x41
        XCTAssertNil(SmartPianist.parse(invalid))
        invalid = volume; invalid[18] = 0x80
        XCTAssertNil(SmartPianist.parse(invalid))
        XCTAssertNil(SmartPianist.set(ParameterKey(.volume),value:[0x80]))
        XCTAssertNil(SmartPianist.set(ParameterKey(.volume),value:[]))
    }
    func testFragmentedPacketAndInterleavedRealtime() {
        var framer = SysExFramer()
        XCTAssertEqual(framer.consume(Array(model.prefix(9))),[])
        XCTAssertEqual(framer.consume([0xF8,0xFE]+Array(model.dropFirst(9))),[model])
    }
    func testMultipleMessagesAndRestartAfterIncompleteSysEx() {
        var framer = SysExFramer()
        XCTAssertEqual(framer.consume([0xF0,0x43,0]+volume+model),[volume,model])
    }
    func testChannelStatusCancelsIncompleteMessage() {
        var framer = SysExFramer()
        XCTAssertEqual(framer.consume([0xF0,0x43,0x90,60,80,0xF7]),[])
        XCTAssertEqual(framer.consume(volume),[volume])
    }
    func testDocumentedVoicesUseZeroBasedProgramNumbers() {
        let grand = PianoVoice.all.first { $0.id == "Grand Piano" }!
        let live = PianoVoice.all.first { $0.id == "Live Grand" }!
        XCTAssertEqual(SmartPianist.decodeInteger(grand.value),0x6C0000)
        XCTAssertEqual(SmartPianist.decodeInteger(live.value),0x6C0201)
        XCTAssertEqual(PianoVoice.all.count,24)
    }
    func testReverbMatchesObservedRecitalHall() {
        XCTAssertEqual(ReverbPreset.all.first { $0.id == "Recital Hall" }?.value,[0,2,24])
        XCTAssertEqual(ReverbPreset.all.first { $0.id == "Concert Hall" }?.value,[0,2,4])
    }
    func testOversizeIntegerDoesNotOverflow() {
        XCTAssertEqual(SmartPianist.decodeInteger(Array(repeating:127,count:500)),0)
    }
}
