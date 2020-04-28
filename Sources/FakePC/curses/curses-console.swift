//
//  curses-console.swift
//  FakePC
//
//  Created by Simon Evans on 24/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Text (MDA) console using curses text mode, screen + keyboard, no mouse.
//


#if canImport(LinuxCurses)
import LinuxCurses
#endif

#if canImport(DarwinCurses)
import DarwinCurses
#endif

import CInternal
import Foundation

func cursesStartupWith(config: MachineConfig) {
    let console = CursesConsole()
    ISA.setConsole(console)
    runVMThreadWith(config: config)
    let kb = console.keyboard as! CursesKeyboard
    kb.keyboardLoop()
}


class CursesKeyboard: PS2Device {
    private weak var controller: I8042?

    enum KeyPress {
        case unshifted(UInt16)
        case shifted(UInt16)
        case control(UInt16)
    }


    private let scanCodes2: [Int32: KeyPress] = [      // KeyCode -> Make
        // a-z
        0x61: .unshifted(0x1C),
        0x62: .unshifted(0x32),
        0x63: .unshifted(0x21),
        0x64: .unshifted(0x23),
        0x65: .unshifted(0x24),
        0x66: .unshifted(0x2B),
        0x67: .unshifted(0x34),
        0x68: .unshifted(0x33),
        0x69: .unshifted(0x43),
        0x6A: .unshifted(0x3B),
        0x6B: .unshifted(0x42),
        0x6C: .unshifted(0x4B),
        0x6D: .unshifted(0x3A),
        // n
        0x6E: .unshifted(0x31),
        0x6F: .unshifted(0x44),
        0x70: .unshifted(0x4D),
        0x71: .unshifted(0x15),
        0x72: .unshifted(0x2D),
        0x73: .unshifted(0x1B),
        0x74: .unshifted(0x2C),
        0x75: .unshifted(0x3C),
        0x76: .unshifted(0x2A),
        0x77: .unshifted(0x1D),
        0x78: .unshifted(0x22),
        0x79: .unshifted(0x35),
        0x7A: .unshifted(0x1A),

        // A-Z
        0x41: .shifted(0x1C),
        0x42: .shifted(0x32),
        0x43: .shifted(0x21),
        0x44: .shifted(0x23),
        0x45: .shifted(0x24),
        0x46: .shifted(0x2B),
        0x47: .shifted(0x34),
        0x48: .shifted(0x33),
        0x49: .shifted(0x43),
        0x4A: .shifted(0x3B),
        0x4B: .shifted(0x42),
        0x4C: .shifted(0x4B),
        0x4D: .shifted(0x3A),
        // N
        0x4E: .shifted(0x31),
        0x4F: .shifted(0x44),
        0x50: .shifted(0x4D),
        0x51: .shifted(0x15),
        0x52: .shifted(0x2D),
        0x53: .shifted(0x1B),
        0x54: .shifted(0x2C),
        0x55: .shifted(0x3C),
        0x56: .shifted(0x2A),
        0x57: .shifted(0x1D),
        0x58: .shifted(0x22),
        0x59: .shifted(0x35),
        0x5A: .shifted(0x1A),

        // A-Z
        0x01: .control(0x1C),
        0x02: .control(0x32),
        0x03: .control(0x21),
        0x04: .control(0x23),
        0x05: .control(0x24),
        0x06: .control(0x2B),
        0x07: .control(0x34),
//      0x08: .control(0x33),       // Handled as TAB key, below
        0x09: .control(0x43),
        0x0A: .control(0x3B),
        0x0B: .control(0x42),
        0x0C: .control(0x4B),
//      0x0D: .control(0x3A),       // Handled as Return key, below
        // N
        0x0E: .control(0x31),
        0x0F: .control(0x44),
        0x10: .control(0x4D),
        0x11: .control(0x15),
        0x12: .control(0x2D),
        0x13: .control(0x1B),
        0x14: .control(0x2C),
        0x15: .control(0x3C),
        0x16: .control(0x2A),
        0x17: .control(0x1D),
        0x18: .control(0x22),
        0x19: .control(0x35),
        0x1A: .control(0x1A),


        // 0-9
        0x30: .unshifted(0x45),
        0x31: .unshifted(0x16),
        0x32: .unshifted(0x1E),
        0x33: .unshifted(0x26),
        0x34: .unshifted(0x25),
        0x35: .unshifted(0x2E),
        0x36: .unshifted(0x36),
        0x37: .unshifted(0x3D),
        0x38: .unshifted(0x3E),
        0x39: .unshifted(0x46),


        // 0-9 shifted characters
        0x21: .shifted(0x16),       // !
        0x40: .shifted(0x1E),       // @
        0x23: .shifted(0x26),       // #
        0x24: .shifted(0x25),       // $
        0x25: .shifted(0x2E),       // %
        0x5e: .shifted(0x36),       // ^
        0x26: .shifted(0x3D),       // &
        0x2a: .shifted(0x3E),       // *
        0x28: .shifted(0x46),       // (
        0x29: .shifted(0x45),       // )


        0x60: .unshifted(0x0E),     // `
        0x7e: .shifted(0x0E),       // ~
        0x2d: .unshifted(0x4E),     // -
        0x5f: .shifted(0x4E),       // _
        0x3d: .unshifted(0x55),     // =
        0x2b: .shifted(0x55),       // +
        0x5b: .unshifted(0x54),     // [
        0x7b: .shifted(0x54),       // {
        0x5d: .unshifted(0x5B),     // ]
        0x7d: .shifted(0x5B),       // }
        0x3b: .unshifted(0x4C),     // ;
        0x3a: .shifted(0x4C),       // :
        0x27: .unshifted(0x52),     // '
        0x22: .shifted(0x52),       // "
        0x5c: .unshifted(0x5D),     // \
        0x7c: .shifted(0x5D),       // |
        0x2c: .unshifted(0x41),     // ,
        0x3c: .shifted(0x41),       // <
        0x2e: .unshifted(0x49),     // .
        0x3e: .shifted(0x49),       // >
        0x2f: .unshifted(0x4A),     // /
        0x3f: .shifted(0x4A),       // ?


        0x102: .unshifted(0xE075),  // Up arrow
        0x103: .unshifted(0xE072),  // Down arrow
        0x104: .unshifted(0xE06B),  // Left arrow
        0x105: .unshifted(0xE074),  // Right arrow

        0x0D: .unshifted(0x5A),     // Return
        0x1B: .unshifted(0x76),     // Escape
        0x20: .unshifted(0x29),     // Space
        0x08: .unshifted(0x0D),     // TAB
        0x7F: .unshifted(0x66),     // Backspace
    ]

    func setController(_ controller: I8042) {
        self.controller = controller
    }


    @discardableResult
    private func sendMakeCodesForScanCode(_ scanCode: UInt16) -> Bool {
        if scanCode > 0xFF {
            let high = UInt8(scanCode >> 8)
            controller?.addScanCode(high)
        }
        let low = UInt8(truncatingIfNeeded: scanCode)
        controller?.addScanCode(low)
        return true
    }


    @discardableResult
    private func sendBreakCodesForScanCode(_ scanCode: UInt16) -> Bool {
        if scanCode > 0xFF {
            let high = UInt8(scanCode >> 8)
            controller?.addScanCode(high)
        }
        controller?.addScanCode(0xF0)   // break
        let low = UInt8(truncatingIfNeeded: scanCode)
        controller?.addScanCode(low)
        return true
    }


    func keyboardLoop() {
        while true {
            let ch = getch()
            if ch == -1 { continue }
            if ch == 0xa7 {
                // Use §/± key as exit for now
                endwin()
                exit(1)
            }
            guard let keyPress = scanCodes2[ch] else {
                let s = String(UnicodeScalar(UInt32(ch)) ?? UnicodeScalar(32))
                debugLog("Unknown key: \(String(ch, radix: 16)): \(s)")
                continue
            }

            switch keyPress {
                case .unshifted(let scanCode):
                    sendMakeCodesForScanCode(scanCode)
                    sendBreakCodesForScanCode(scanCode)

                case .shifted(let scanCode):
                    sendMakeCodesForScanCode(0x12) // Left Shift
                    sendMakeCodesForScanCode(scanCode)
                    sendBreakCodesForScanCode(scanCode)
                    sendBreakCodesForScanCode(0x12) // Left Shift

                case .control(let scanCode):
                    sendMakeCodesForScanCode(0x14) // Left Control
                    sendMakeCodesForScanCode(scanCode)
                    sendBreakCodesForScanCode(scanCode)
                    sendBreakCodesForScanCode(0x14) // Left Control
            }
        }
    }
}


class CursesConsole: Console {
    let keyboard: PS2Device?
    let mouse: PS2Device? = nil

    var updateHandler: (() -> ())?
    let log: FileHandle

    init() {
        setlocale(LC_ALL, "")
        initscr()
        cbreak()
        noecho()
        nonl()
        halfdelay(2)
        intrflush(stdscr, false)
        keypad(stdscr, true)
        keyboard = CursesKeyboard()
        let url = URL(fileURLWithPath: "logfile")
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try! Data().write(to: url)
        }
        log = try! FileHandle(forWritingTo: url)
        log.seekToEndOfFile()
    }


    func setWindow(screenMode: ScreenMode) {
    }


    func updateDisplay() {
        if let handler = updateHandler {
            handler()
        }
    }


    func rasteriseTextMemory(screenMode: ScreenMode, font: Font,
                             newCharacter: (_ row: Int, _ column: Int) -> (character: UInt8, attribute: UInt8)?) {
        for row in 0..<screenMode.textRows {
            for column in 0..<screenMode.textColumns {
                if let (character, _) = newCharacter(row, column) {
                    writeCharAtRowColumn(Int32(row), Int32(column), character)
                }
            }
        }
        refresh()
    }


    func debugLog(_ entry: String) {
        log.write(Data("DEBUG: ".utf8))
        log.write(Data(entry.utf8))
        log.write(Data("\n".utf8))
    }
}
