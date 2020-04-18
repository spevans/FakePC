//
//  cocoa-keyboard.swift
//  FakePC
//
//  Created by Simon Evans on 18/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
// Implements a PS2 Keyboard. Mostly converting NSEvents to Keyboard Scan Codes.

#if os(macOS)

import Cocoa

class Keyboard: NSResponder, PS2Device {

    private weak var controller: I8042?


    func setController(_ controller: I8042) {
        self.controller = controller
    }

/*
     // Type 1 codes
    static private let scanCodes: [UInt16: UInt8] = [      // KeyCode -> (Make, Break)
        0x00: 0x1E,     // A
        0x01: 0x1F,     // S
        0x02: 0x20,     // D
        0x03: 0x21,     // F
        0x04: 0x23,     // H
        0x05: 0x22,     // G
        0x06: 0x2C,     // Z
        0x07: 0x2D,     // X
        0x08: 0x20,     // C
        0x09: 0x2F,     // V
        0x0B: 0x30,     // B
        0x0C: 0x10,     // Q
        0x0D: 0x11,     // W
        0x0E: 0x12,     // E
        0x0F: 0x13,     // R

        0x10: 0x15,     // Y
        0x11: 0x14,     // T
        0x12: 0x02,     // 1
        0x13: 0x03,     // 2
        0x14: 0x04,     // 3
        0x15: 0x05,     // 4
        0x16: 0x07,     // 6
        0x17: 0x06,     // 5
        0x18: 0x0D,     // =
        0x19: 0x0A,     // 9
        0x1A: 0x08,     // 7
        0x1B: 0x0C,     // -
        0x1C: 0x09,     // 8
        0x1D: 0x0B,     // 0
        0x1E: 0x1B,     // ]
        0x1F: 0x18,     // O

        0x20: 0x16,     // U
        0x21: 0x1A,     // [
        0x22: 0x17,     // I
        0x23: 0x19,     // P
        0x24: 0x1C,     // Return
        0x25: 0x26,     // L
        0x26: 0x24,     // J
        0x27: 0x33,     // '
        0x28: 0x25,     // K
        0x29: 0x27,     // ;
        0x2A: 0x2B,     // \
        0x2B: 0x33,     // ,
        0x2C: 0x35,     // /
        0x2D: 0x31,     // N
        0x2E: 0x32,     // M
        0x2F: 0x34,     // .

        0x30: 0x0F,     // Tab
        0x31: 0x39,     // Space
//        0x32:        ~
        0x33: 0x53,     // Delete
//        0x34:
        0x35: 0x01,     // Esc
//        0x36:         // Right Cmd        - flags changed
//        0x37:         // Left Cmd (Apple) - flags changed
        0x38: 0x2A,     // Left Shift       - flags changed
        0x39: 0x3A,     // Caps Lock        - flags changed
        0x3A: 0x38,     // Left Option      - flags changed - mapped to Left ALT
        0x3B: 0x1D,     // Left Control     - flags changed
        0x3C: 0x36,     // Right Shift      - flags changed
//        0x3D            // Right Option     - flags changed
//        0x3E            // Right Control
//        0x3F

//        0x40
        0x41: 0x53,     // Numeric Keypad .
//        0x42
        0x43: 0x37,     // Numeric Keypad *
//        0x44
        0x45: 0x4E,     // Numeric Keypad +
//        0x46
//        0x47
//        0x48
//        0x49
//        0x4A
//        0x4B        Numeric Keypad /
//        0x4C        Numeric Keypad Enter
//        0x4D
        0x4E: 0x4A,     // Numeric Keypad -
//        0x4F

//        0x50
//        0x51        Numeric Keypad =
        0x52: 0x52, // Numeric Keypad 0
        0x53: 0x4F, // Numeric Keypad 1
        0x54: 0x50, // Numeric Keypad 2
        0x55        // Numeric Keypad 3
        0x56        // Numeric Keypad 4
        0x57        // Numeric Keypad 5
        0x58        // Numeric Keypad 6
        0x59        // Numeric Keypad 7
        0x5A
        0x5B        // Numeric Keypad 8
        0x5C        // Numeric Keypad 9
        0x5D
        0x5E
        0x5F

        0x60        F5
        0x61        F6
        0x62        F7
        0x63        F3
        0x64        F8
        0x65        F9
        0x66
        0x67        F11
        0x68
        0x69        F13
        0x6A
        0x6B        F14
        0x6C
        0x6D        F10
        0x6E
        0x6F        F12

        0x70
        0x71        F15
        0x72        Help
        0x73        Home
        0x74        Page Up
        0x75        Del (Below the Help Key)
        0x76        F4
        0x77        End
        0x78        F2
        0x79        Page Down
        0x7A        F1
        0x7B        Left Arrow
        0x7C        Right Arrow
        0x7D        Down Arrow
        0x7E        Up Arrow

    ]*/



    override func keyDown(with event: NSEvent) {
        NSLog("keyDown: \(event)")
        NSLog("code: \(String(event.keyCode, radix: 16)) modfier flags: \(event.modifierFlags)")
    }

    override func keyUp(with event: NSEvent) {
        NSLog("keyUp: \(event)")
        NSLog("code: \(String(event.keyCode, radix: 16)) modfier flags: \(event.modifierFlags)")
    }

    override func flagsChanged(with event: NSEvent) {
        switch event.type {
            case .keyUp:
                NSLog("UP: \(event.keyCode)")

            case .keyDown:
                NSLog("DOWN: \(event.keyCode)")

            case .flagsChanged:

                NSLog("Code: \(event.keyCode) 0x\(String(event.keyCode, radix: 16))")
                let m = event.modifierFlags
                NSLog("Control \(m.contains(.control)) CapsLock: \(m.contains(.capsLock)) Shift: \(m.contains(.shift)) Option: \(m.contains(.option)) Command:  \(m.contains(.command))")
            default:
                NSLog("ignoreing \(event.type.rawValue)")
        }

    }
}

#endif
