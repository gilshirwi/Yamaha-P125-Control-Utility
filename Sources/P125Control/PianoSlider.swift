import AppKit
import SwiftUI

/// A single native control owns dragging, double-click and wheel events. Its
/// local drag position is drawn immediately, independently of MIDI roundtrips.
struct PianoSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var enabled = true
    var vertical = false
    var color: Color = Color(red:0.49,green:0.86,blue:0.76)
    var step: Double = 1
    var onReset: () -> Void

    func makeNSView(context:Context) -> PianoSliderView { PianoSliderView() }
    func updateNSView(_ view:PianoSliderView,context:Context) {
        view.minimum = range.lowerBound; view.maximum = range.upperBound
        view.enabled = enabled; view.vertical = vertical
        view.tint = NSColor(color); view.step = step
        view.onChange = { value = $0 }; view.onReset = onReset
        view.externalValue = value
        view.setAccessibilityEnabled(enabled)
        view.setAccessibilityMinValue(range.lowerBound)
        view.setAccessibilityMaxValue(range.upperBound)
        view.setAccessibilityValue(value)
        view.needsDisplay = true
    }
}

final class PianoSliderView: NSView {
    var minimum:Double = 0
    var maximum:Double = 127
    var externalValue:Double = 0
    var enabled = true
    var vertical = false
    var step:Double = 1
    var tint = NSColor.controlAccentColor
    var onChange: ((Double) -> Void)?
    var onReset: (() -> Void)?
    private var dragValue:Double?
    private var wheelValue:Double?
    private var lastWheel = Date.distantPast
    override var acceptsFirstResponder:Bool { enabled }

    override init(frame:NSRect) {
        super.init(frame:frame)
        setAccessibilityElement(true); setAccessibilityRole(.slider)
    }
    required init?(coder:NSCoder) { super.init(coder:coder) }

    override func draw(_ dirtyRect:NSRect) {
        let position = dragValue ?? externalValue
        let fraction = max(0,min(1,(position-minimum)/max(1,maximum-minimum)))
        let inset:CGFloat = 8
        let travel = max(1,(vertical ? bounds.height : bounds.width)-inset*2)
        let track = vertical ? NSRect(x:bounds.midX-2,y:inset,width:4,height:travel) : NSRect(x:inset,y:bounds.midY-2,width:travel,height:4)
        NSColor.white.withAlphaComponent(enabled ? 0.12 : 0.04).setFill()
        NSBezierPath(roundedRect:track,xRadius:2,yRadius:2).fill()
        let filled = vertical ? NSRect(x:track.minX,y:track.minY,width:4,height:travel*fraction) : NSRect(x:track.minX,y:track.minY,width:travel*fraction,height:4)
        tint.withAlphaComponent(enabled ? 0.6 : 0.15).setFill()
        NSBezierPath(roundedRect:filled,xRadius:2,yRadius:2).fill()
        let center = vertical ? NSPoint(x:bounds.midX,y:inset+travel*fraction) : NSPoint(x:inset+travel*fraction,y:bounds.midY)
        let thumb = vertical ? NSRect(x:center.x-13,y:center.y-4.5,width:26,height:9) : NSRect(x:center.x-7,y:center.y-7,width:14,height:14)
        (vertical ? tint : NSColor(calibratedWhite:0.65,alpha:1)).withAlphaComponent(enabled ? 1 : 0.3).setFill()
        NSBezierPath(roundedRect:thumb,xRadius:vertical ? 3 : 7,yRadius:vertical ? 3 : 7).fill()
        if window?.firstResponder === self {
            tint.withAlphaComponent(0.4).setStroke()
            NSBezierPath(roundedRect:thumb.insetBy(dx:-3,dy:-3),xRadius:8,yRadius:8).stroke()
        }
    }

    override func mouseDown(with event:NSEvent) {
        guard enabled else { return }
        window?.makeFirstResponder(self)
        if event.clickCount >= 2 {
            dragValue = nil; wheelValue = nil
            onReset?(); needsDisplay = true
            return
        }
        updateDrag(event)
    }
    override func mouseDragged(with event:NSEvent) {
        guard enabled, dragValue != nil else { return }
        updateDrag(event)
    }
    override func mouseUp(with event:NSEvent) {
        guard let final = dragValue else { return }
        externalValue = final; dragValue = nil
        onChange?(final); needsDisplay = true
    }
    private func updateDrag(_ event:NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        let travel = max(1,(vertical ? bounds.height : bounds.width)-16)
        let fraction = max(0,min(1,((vertical ? point.y : point.x)-8)/travel))
        let value = minimum + fraction*(maximum-minimum)
        dragValue = value; wheelValue = nil
        onChange?(value); needsDisplay = true
    }
    override func scrollWheel(with event:NSEvent) {
        guard enabled else { super.scrollWheel(with:event); return }
        guard event.momentumPhase == [] else { return }
        if Date().timeIntervalSince(lastWheel) > 0.3 { wheelValue = externalValue }
        lastWheel = Date()
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.1 : event.deltaY
        let next = clamp((wheelValue ?? externalValue) + delta*step)
        wheelValue = next; externalValue = next
        onChange?(next); needsDisplay = true
    }
    override func keyDown(with event:NSEvent) {
        switch event.keyCode {
        case 123,125: adjust(-step)
        case 124,126: adjust(step)
        default: super.keyDown(with:event)
        }
    }
    override func accessibilityPerformIncrement() -> Bool { guard enabled else { return false }; adjust(step); return true }
    override func accessibilityPerformDecrement() -> Bool { guard enabled else { return false }; adjust(-step); return true }
    private func adjust(_ delta:Double) {
        externalValue = clamp(externalValue+delta); wheelValue = nil
        onChange?(externalValue); needsDisplay = true
    }
    private func clamp(_ value:Double) -> Double { max(minimum,min(maximum,value)) }
}
