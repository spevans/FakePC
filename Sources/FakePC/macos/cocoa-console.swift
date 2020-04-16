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


class Console {
    private let window: NSWindow
    private let lock = NSLock()
    private var screen: Screen?
    private var fontCache: [NSImage?]
    var updateHandler: (() -> ())?


    init() {
        fontCache = Array<NSImage?>(repeating: nil, count: 256)
        let rect = NSRect(x: 100, y: 100, width: 1, height: 1)
        let mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullScreen]
        window = NSWindow(contentRect: rect, styleMask: mask, backing: .buffered, defer: false)
        window.hasShadow = true
        window.title = "VGA"
        window.orderFront(nil)
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
            let newScreen = Screen(frame: frame, display: self)
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


    func rasteriseTextMemory(screenMode: ScreenMode, font: Font, newCharacter: (Int, Int) -> (UInt8, UInt8)?) {

        func characterImage(character: UInt8, attribute: UInt8) -> NSImage {
            let offset = (Int(character) * font.characterSize)
            let ptr = font.fontData.advanced(by: offset)
            let arrayPtr: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>? = UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>.allocate(capacity: 1)
            arrayPtr!.pointee = UnsafeMutablePointer(mutating: ptr)

            let imagerep = NSBitmapImageRep(bitmapDataPlanes: arrayPtr,
                                            pixelsWide: font.width,
                                            pixelsHigh: font.height,
                                            bitsPerSample: 1,
                                            samplesPerPixel: 1,
                                            hasAlpha: false,
                                            isPlanar: false,
                                            colorSpaceName: NSColorSpaceName.calibratedWhite,
                                            bytesPerRow: font.bytesPerRow,
                                            bitsPerPixel: 1)
            let image = NSImage()
            image.addRepresentation(imagerep!)
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
                    if let image = fontCache[Int(character)] {
                        charImage = image
                    } else {
                        charImage = characterImage(character: character, attribute: attribute)
                        fontCache[Int(character)] = charImage
                    }
                    let rect = NSRect(x: column * Int(screenMode.textWidth),
                                      y: (screenMode.textRows - row - 1) * font.height,
                                      width: font.width,
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

    private unowned let display: Console
    fileprivate var bitmapImage: NSBitmapImageRep


    init(frame: NSRect, display: Console) {
        self.display = display

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
