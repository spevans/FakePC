//
//  cocoa-console.swift
//  FakePC
//
//  Created by Simon Evans on 15/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Cocoa interface between the system and the host OS screen, keyboard and mouse.
//

#if os(macOS)

import Cocoa
import BABAB


// VGA RAMDAC is 18bit, 6bits per colour
fileprivate struct VGAPaletteEntry {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    static let black = VGAPaletteEntry(red: 0x0, green: 0, blue: 0)
    static let blue = VGAPaletteEntry(red: 0x0, green: 0, blue: 0xAA)
    static let green = VGAPaletteEntry(red: 0x0, green: 0xAA, blue: 0)
    static let cyan = VGAPaletteEntry(red: 0x0, green: 0xAA, blue: 0xAA)
    static let red = VGAPaletteEntry(red: 0xAA, green: 0, blue: 0)
    static let magenta = VGAPaletteEntry(red: 0xAA, green: 0, blue: 0xAA)
    static let brown = VGAPaletteEntry(red: 0xAA, green: 0x55, blue: 0)
    static let lightgrey = VGAPaletteEntry(red: 0xAA, green: 0xAA, blue: 0xAA)

    static let darkgrey = VGAPaletteEntry(red: 0x55, green: 0x55, blue: 0x55)
    static let brightBlue = VGAPaletteEntry(red: 0x55, green: 0x55, blue: 0xFF)
    static let brightGreen = VGAPaletteEntry(red: 0x55, green: 0xFF, blue: 0x55)
    static let brightCyan = VGAPaletteEntry(red: 0x55, green: 0xFF, blue: 0xFF)
    static let brightRed = VGAPaletteEntry(red: 0xFF, green: 0x55, blue: 0x55)
    static let brightMagenta = VGAPaletteEntry(red: 0xFF, green: 0x55, blue: 0xFF)
    static let brightYellow = VGAPaletteEntry(red: 0xFF, green: 0xFF, blue: 0x55)
    static let brightWhite = VGAPaletteEntry(red: 0xFF, green: 0xFF, blue: 0xFF)

}

// FIXME: In the future the palette should be loaded from the card's memory
private let textPalette: [VGAPaletteEntry] = [
    .black, .blue, .green, .cyan, .red, .magenta, .brown, .lightgrey,
    .darkgrey, .brightBlue, .brightGreen, .brightCyan, .brightRed, .brightMagenta, .brightYellow, .brightWhite
]



class CocoaConsole: Console {
    private let window: NSWindow
    private let lock = NSLock()
    private var screen: Screen?

    let keyboard: PS2Device? = Keyboard()
    let mouse: PS2Device? = nil
    private var fontCache: [UInt16: NSImage] = [:]
    var updateHandler: (() -> ())?


    init() {
        let rect = NSRect(x: 100, y: 100, width: 1, height: 1)
        let mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullScreen]
        window = NSWindow(contentRect: rect, styleMask: mask, backing: .buffered, defer: false)
        window.hasShadow = true
        window.title = "VGA"
        window.orderFront(nil)
        guard let responder = keyboard as? NSResponder else {
            fatalError("Cant cast keyboard as NSResponsder")
        }
        window.makeFirstResponder(responder)
    }


    func setWindow(screenMode: ScreenMode) {
        DispatchQueue.main.async {
            let window = self.window
            let height = CGFloat(screenMode.heightInPixels) + 22 // For status bar
            let width = CGFloat(screenMode.widthInPixels)
            let origin = window.frame.origin
            let newFrame = NSRect(x: origin.x, y: origin.y, width: width, height: height)
            window.setFrame(newFrame, display: true, animate: false)
            let fixedSize = NSSize(width: width, height: height)
            window.minSize = fixedSize
            window.maxSize = fixedSize

            self.screen?.removeFromSuperview()
            let frame = NSRect(x: 0, y: 0, width: width, height: height)
            let newScreen = Screen(frame: frame, display: self, mouse: nil)
            window.contentView?.addSubview(newScreen)
            newScreen.needsDisplay = true
            newScreen.needsLayout = true
            self.screen = newScreen
        }
    }


    func updateDisplay() {
        if let screen = self.screen {
            DispatchQueue.main.async {
                screen.needsDisplay = true
            }
        }
    }

    var screenDump = ""
    private func dumpTextMemory(screenMode: ScreenMode, newCharacter: (Int, Int) -> (character: UInt8, attribute: UInt8)?) -> String {
        var line = ""
        for row in 0..<screenMode.textRows {
            for column in 0..<screenMode.textColumns {
                let (character, attribute) = newCharacter(row, column)!
                let ch = (character >= 32 && character < 127) ? String(Character(Unicode.Scalar(character))) : "?"
                let attr = hexNum(attribute)
                line.append("\(ch)\(attr) ")
            }
            line.append("\n")
        }
        return line
    }


    func rasteriseTextMemory(screenMode: ScreenMode, font: Font, newCharacter: (Int, Int) -> (character: UInt8, attribute: UInt8)?) {

        //        if screenMode.isTextMode {
        //            screenDump = dumpTextMemory(screenMode: screenMode, newCharacter: newCharacter)
        //        }

        func characterImage(character: UInt8, attribute: UInt8) -> NSImage {
            precondition(font.width.isMultiple(of: 8))
            let offset = (Int(character) * font.characterSize)
            let ptr = font.fontData.advanced(by: offset)
            let characterData = UnsafeBufferPointer<UInt8>(start: ptr, count: font.bytesPerRow * font.height)
            precondition(font.width == screenMode.textWidth || font.width == screenMode.textWidth - 1)
            let imagerep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(screenMode.textWidth),
                                            pixelsHigh: font.height,
                                            bitsPerSample: 8,
                                            samplesPerPixel: 3,
                                            hasAlpha: false,
                                            isPlanar: false,
                                            colorSpaceName: NSColorSpaceName.calibratedRGB,
                                            bytesPerRow: Int(screenMode.textWidth) * 3,
                                            bitsPerPixel: 24)!

            // Convert the source font bitmap into 8bits per pixel with the colour set to the attribute
            var srcIdx = 0
            var bitmapIdx = 0
            let bitmapBuffer = UnsafeMutableBufferPointer(start: imagerep.bitmapData!, count: Int(screenMode.textWidth) * font.height * 3)

            let foregroundColour = textPalette[Int(attribute & 0xf)]
            let backgroundColour = textPalette[Int((attribute >> 4) & 0xf)]

            for _ in 0..<font.height {
                for _ in 0..<font.bytesPerRow {
                    let srcByte = characterData[srcIdx]
                    srcIdx += 1
                    for x: UInt8 in 0...7 {
                        let bit = 1 << (7 - x)
                        let colour = (srcByte & bit) == 0 ? backgroundColour : foregroundColour
                        bitmapBuffer[bitmapIdx + 0] = colour.red
                        bitmapBuffer[bitmapIdx + 1] = colour.green
                        bitmapBuffer[bitmapIdx + 2] = colour.blue
                        bitmapIdx += 3

                        if x == 7 && screenMode.textWidth == (font.width + 1) {
                            // Repeat the last column of a 8pixels wide font if the screen mode is 9pixels wide to emulate the text mode stretch
                            bitmapBuffer[bitmapIdx + 0] = colour.red
                            bitmapBuffer[bitmapIdx + 1] = colour.green
                            bitmapBuffer[bitmapIdx + 2] = colour.blue
                            bitmapIdx += 3
                        }
                    }
                }
            }

            let image = NSImage()
            image.addRepresentation(imagerep)
            return image
        }

        guard let bitmap = self.screen?.bitmapImage else { return }
        lock.lock()
        guard let ctx = NSGraphicsContext(bitmapImageRep: bitmap) else {
            lock.unlock()
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        for row in 0..<screenMode.textRows {
            for column in 0..<screenMode.textColumns {
                if let (character, attribute) = newCharacter(row, column) {
                    let charImage: NSImage
                    let cacheKey = UInt16(UInt16(attribute) << 8 | UInt16(character))
                    if let image = fontCache[cacheKey] {
                        charImage = image
                    } else {
                        charImage = characterImage(character: character, attribute: attribute)
                        fontCache[cacheKey] = charImage
                    }
                    let rect = NSRect(x: column * Int(screenMode.textWidth),
                                      y: (screenMode.textRows - row - 1) * font.height,
                                      width: Int(screenMode.textWidth),
                                      height: font.height)

                    charImage.draw(in: rect)
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        lock.unlock()
    }
}


private class Screen: NSView {

    private unowned let display: CocoaConsole
    private let mouse: NSResponder?
    fileprivate var bitmapImage: NSBitmapImageRep


    init(frame: NSRect, display: CocoaConsole, mouse: NSResponder?) {
        self.display = display
        self.mouse = mouse

        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(frame.width),
                                            pixelsHigh: Int(frame.height),
                                            bitsPerSample: 8,
                                            samplesPerPixel: 4,
                                            hasAlpha: true,
                                            isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bitmapFormat: .alphaFirst,
                                            bytesPerRow: 0,
                                            bitsPerPixel: 0) else {
            fatalError("Cant allocate NSBitmapImageRep")
        }

        // Set the screen to black
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: bitmap) {
            NSGraphicsContext.current = ctx
            let rect = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
            let path = NSBezierPath(rect: rect)
            NSColor.black.set()
            path.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        self.bitmapImage = bitmap
        super.init(frame: frame)
    }


    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    override func draw(_ dirtyRect: NSRect) {
        if let handler = display.updateHandler {
            handler()
            bitmapImage.draw(in: dirtyRect)
        }
    }
}

#endif
