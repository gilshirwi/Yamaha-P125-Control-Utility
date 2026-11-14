import AppKit
import Foundation

let image = NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
let bounds = NSRect(x:48,y:48,width:928,height:928)
let shape = NSBezierPath(roundedRect:bounds,xRadius:204,yRadius:204)
NSGradient(starting:NSColor(calibratedRed:0.18,green:0.22,blue:0.25,alpha:1),ending:NSColor(calibratedRed:0.07,green:0.09,blue:0.11,alpha:1))!.draw(in:shape,angle:270)
NSColor.white.withAlphaComponent(0.12).setStroke(); shape.lineWidth = 3; shape.stroke()
let mint = NSColor(calibratedRed:0.49,green:0.86,blue:0.76,alpha:1)
let text = "P125" as NSString
text.draw(at:NSPoint(x:172,y:610),withAttributes:[.font:NSFont.systemFont(ofSize:178,weight:.light),.foregroundColor:NSColor(calibratedWhite:0.92,alpha:1)])
let small = "CONTROL" as NSString
small.draw(at:NSPoint(x:186,y:552),withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:28,weight:.medium),.foregroundColor:mint,.kern:9])
for i in 0..<7 {
    let key = NSBezierPath(roundedRect:NSRect(x:174+i*98,y:194,width:88,height:290),xRadius:15,yRadius:15)
    (i == 2 ? mint : NSColor(calibratedWhite:0.90,alpha:1)).setFill(); key.fill()
}
for i in [0,1,3,4,5] {
    NSColor(calibratedRed:0.09,green:0.11,blue:0.13,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:235+i*98,y:316,width:55,height:180),xRadius:9,yRadius:9).fill()
}
image.unlockFocus()
let data = image.tiffRepresentation!
let bitmap = NSBitmapImageRep(data:data)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
