//
//  video.swift
//  FakePC
//
//  Created by Simon Evans on 01/01/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Display Adaptor interface and INT 10h BIOS calls.
//

import HypervisorKit
import CFakePC
import Foundation

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif


struct Font {
    let fontData: UnsafePointer<UInt8>
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let characterSize: Int  // in bytes


    init(width: Int, height: Int, data: UnsafeRawPointer) {
        self.width = width
        self.height = height

        bytesPerRow = (width + 7) / 8
        characterSize = height * bytesPerRow
        self.fontData = data.bindMemory(to: UInt8.self, capacity: 256 * characterSize)
    }


    func characterData(character: UInt8) -> UnsafeBufferPointer<UInt8> {
        let offset = (Int(character) * characterSize)
        return  UnsafeBufferPointer<UInt8>(start: fontData + offset, count: characterSize)
    }
}


class Video: ISAIOHardware {

    private let vram: MemoryRegion
    private let font: Font
    private(set) var screenMode: ScreenMode
    private var display: Console
    private var timer: Timer?


    init(vm: VirtualMachine, display: Console) throws {
        self.vram = try vm.addMemory(at: 0xA0000, size: 0x20000) // 128k VRAM
        screenMode = ScreenMode.screenModeFor(mode: 7)!
        font = Font(width: 8, height: 16, data: font_vga_8x16.data)
        self.display = display
        self.display.updateHandler = { self.updateDisplay() }
        self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                self.updateDisplay()
        }
    }


    private func updateDisplay() {
        display.rasteriseTextMemory(screenMode: screenMode, font: font) { (row: Int, column: Int) -> (UInt8, UInt8)? in

            var offset = (row * screenMode.textColumns) + column
            offset *= 2
            let vramPtr = vram.rawBuffer.baseAddress!.advanced(by: offset)
            let value = vramPtr.load(as: UInt16.self)
            let ch = UInt8(truncatingIfNeeded: value)
            let attribute = UInt8(value >> 8)
            return (ch, attribute)
        }
    }


    // BIOS function support. FIXME: Most of these that just access the video memory should be moved
    // in to the ROM BIOS code and directly read/write the video memory at some point
    func setVideo(mode: UInt8) {
        logger.debug("setVideoMode(\(mode))")

        //        let clearScreen = (mode & 0x80) == 0
        guard let newMode = ScreenMode.screenModeFor(mode: Int(mode & 0x3f)) else {
            logger.debug("Unsupported video mode")
            return
        }

        screenMode = newMode
        var bda = BDA()
        bda.activeVideoMode = mode & 0xf
        bda.textColumnsPerRow = UInt16(screenMode.textColumns)
        // FIXME - this value is probably wrong
        bda.activeVideoPageSize = UInt16(truncatingIfNeeded: screenMode.videoPageSize)
        bda.activeVideoPageOffset = 0
        bda.cursorPositionForPage0 = 0
        bda.cursorPositionForPage1 = 0
        bda.cursorPositionForPage2 = 0
        bda.cursorPositionForPage3 = 0
        bda.cursorPositionForPage4 = 0
        bda.cursorPositionForPage5 = 0
        bda.cursorPositionForPage6 = 0
        bda.cursorPositionForPage7 = 0
        bda.cursorShape = UInt16(screenMode.textHeight - 2) << 8 | UInt16(screenMode.textHeight - 1)
        bda.activeVideoPage = 0
        bda.numberOfVideoRows = UInt8(screenMode.textRows - 1)
        bda.scanLinesPerCharacter = screenMode.textHeight
        display.setWindow(screenMode: screenMode)
    }


    func readCharacterAndColorAtCursor(page: UInt8) -> (UInt8, UInt8) {
        let bda = BDA()
        let cursor = bda.cursorPositionForPage0
        let cursorX = Int(cursor & 0xff)
        let cursorY = Int(cursor >> 8)

        let vramBuffer = vram.rawBuffer
        var offset = cursorY * Int(screenMode.textColumns) + cursorX
        offset *= 2
        let character = vramBuffer[offset]
        let color = vramBuffer[offset + 1]
        return (color, character)
    }


    private func writeCharAndColor(character: UInt8, page: UInt8, color: UInt8, x: Int, y: Int) {
        let vramBuffer = vram.rawBuffer
        var offset = y * Int(screenMode.textColumns) + x
        offset *= 2
        vramBuffer[offset] = character
        vramBuffer[offset + 1] = color
        display.updateDisplay()
    }


    func scrollUp(lines: UInt8, color: UInt8, startRow: UInt8, startColumn: UInt8, endRow: UInt8, endColumn: UInt8) {
        guard startRow < endRow else { return }
        guard startColumn < endColumn else { return }

        let vramBuffer = vram.rawBuffer.baseAddress!

        let value = UInt16(color) << 8 | UInt16(0x20)
        let widthInCharacters = Int(1 + endColumn - startColumn)
        if lines == 0 || lines > (endRow - startRow) {
            // clear the region
            for row in startRow...endRow {
                var offset = Int(row) * Int(screenMode.textColumns) + Int(startColumn)
                offset *= 2
                vramBuffer.advanced(by: offset).initializeMemory(as: UInt16.self, repeating: value, count: widthInCharacters)
            }
        } else {
            // scroll the region
            for row in startRow..<endRow {
                var offset = Int(row) * Int(screenMode.textColumns) + Int(startColumn)
                offset *= 2
                let offset2 = offset + (2 * Int(screenMode.textColumns))
                vramBuffer.advanced(by: offset).copyMemory(from: vramBuffer.advanced(by: offset2), byteCount: 2 * widthInCharacters)
            }
            let offset = 2 * (Int(endRow) * Int(screenMode.textColumns) + Int(startColumn))
            // Clear the last row
            vramBuffer.advanced(by: offset).initializeMemory(as: UInt16.self, repeating: value, count: widthInCharacters)
        }
        display.updateDisplay()
    }


    func scrollDown(lines: UInt8, color: UInt8, startRow: UInt8, startColumn: UInt8, endRow: UInt8, endColumn: UInt8) {
        guard startRow < endRow else { return }
        guard startColumn < endColumn else { return }

        let vramBuffer = vram.rawBuffer.baseAddress!

        let value = UInt16(color) << 8 | UInt16(0x20)
        let widthInCharacters = Int(1 + endColumn - startColumn)
        if lines == 0 || lines > (endRow - startRow) {
            // clear the region
            for row in startRow...endRow {
                var offset = Int(row) * Int(screenMode.textColumns) + Int(startColumn)
                offset *= 2
                vramBuffer.advanced(by: offset).initializeMemory(as: UInt16.self, repeating: value, count: widthInCharacters)
            }
        } else {
            // scroll the region
            for row in ((startRow + 1)...endRow).reversed() {
                var offset = Int(row) * Int(screenMode.textColumns) + Int(startColumn)
                offset *= 2
                let offset2 = offset - (2 * Int(screenMode.textColumns))
                vramBuffer.advanced(by: offset).copyMemory(from: vramBuffer.advanced(by: offset2), byteCount: 2 * widthInCharacters)
            }
            let offset = 2 * (Int(startRow) * Int(screenMode.textColumns) + Int(startColumn))
            // Clear the last row
            vramBuffer.advanced(by: offset).initializeMemory(as: UInt16.self, repeating: value, count: widthInCharacters)
        }
        display.updateDisplay()
    }


    func writeCharacterAndColorAtCursor(character: UInt8, page: UInt8, color: UInt8, count: UInt16) {
        guard count > 0 else { return  }
        let bda = BDA()
        let cursor = bda.cursorPositionForPage0
        var cursorX = Int(cursor & 0xff)
        var cursorY = Int(cursor >> 8)

        for _ in 0..<count {
            writeCharAndColor(character: character, page: page, color: color, x: cursorX, y: cursorY)
            cursorX += 1
            if cursorX == screenMode.textColumns {
                cursorX = 0
                cursorY += 1
                if cursorY >= screenMode.textRows {
                    break
                }
            }
        }
        display.updateDisplay()
    }


    func ttyOutput(character: UInt8, page: UInt8, color: UInt8) {
        var bda = BDA()
        let cursor = bda.cursorPositionForPage0
        var cursorX = Int(cursor & 0xff)
        var cursorY = Int(cursor >> 8)

        switch character {
            case 0x8: // Backspace
                cursorX -= 1
                if cursorX < 0 {
                    cursorX = Int(screenMode.textColumns)
                    cursorY -= 1
                    if cursorY < 0 { cursorY = 0 }
            }

            case 0xD: // Carriage Return
                cursorX = 0

            case 0xA: // Linefeed
                cursorY += 1
                if cursorY >= Int(screenMode.textRows) {
                    cursorY = Int(screenMode.textRows - 1)
                    scrollUp(lines: 1, color: 07, startRow: 0, startColumn: 0, endRow: UInt8(screenMode.textRows - 1), endColumn: UInt8(screenMode.textColumns - 1))
            }

            default:
                writeCharAndColor(character: character, page: page, color: color, x: cursorX, y: cursorY)
                cursorX += 1
                if cursorX >= Int(screenMode.textColumns) {
                    cursorX = 0
                    cursorY += 1
                    if cursorY >= Int(screenMode.textRows) {
                        scrollUp(lines: 1, color: 07, startRow: 0, startColumn: 0, endRow: UInt8(screenMode.textRows - 1), endColumn: UInt8(screenMode.textColumns - 1))
                        cursorY = Int(screenMode.textRows - 1)
                    }
            }
        }
        bda.cursorPositionForPage0 = UInt16(cursorY << 8) | UInt16(cursorX)
    }
}
