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


    // Type 2 codes, the break code is 'F0' <make code>, except for E0 codes where the break is 'E0' 'F0' <make code>
    private let scanCodes2: [UInt16: UInt16] = [      // KeyCode -> Make
        0x00: 0x1C,     // A
        0x01: 0x1B,     // S
        0x02: 0x23,     // D
        0x03: 0x2B,     // F
        0x04: 0x33,     // H
        0x05: 0x34,     // G
        0x06: 0x1A,     // Z
        0x07: 0x22,     // X
        0x08: 0x21,     // C
        0x09: 0x2A,     // V
        0x0B: 0x32,     // B
        0x0C: 0x15,     // Q
        0x0D: 0x1D,     // W
        0x0E: 0x24,     // E
        0x0F: 0x2D,     // R

        0x10: 0x35,     // Y
        0x11: 0x2C,     // T
        0x12: 0x16,     // 1
        0x13: 0x1E,     // 2
        0x14: 0x26,     // 3
        0x15: 0x25,     // 4
        0x16: 0x36,     // 6
        0x17: 0x2E,     // 5
        0x18: 0x55,     // =
        0x19: 0x46,     // 9
        0x1A: 0x3D,     // 7
        0x1B: 0x4E,     // -
        0x1C: 0x3E,     // 8
        0x1D: 0x45,     // 0
        0x1E: 0x5B,     // ]
        0x1F: 0x44,     // O

        0x20: 0x3C,     // U
        0x21: 0x54,     // [
        0x22: 0x43,     // I
        0x23: 0x4D,     // P
        0x24: 0x5A,     // Return
        0x25: 0x4B,     // L
        0x26: 0x3B,     // J
        0x27: 0x52,     // '
        0x28: 0x42,     // K
        0x29: 0x4C,     // ;
        0x2A: 0x5D,     // \
        0x2B: 0x41,     // ,
        0x2C: 0x4A,     // /
        0x2D: 0x31,     // N
        0x2E: 0x3A,     // M
        0x2F: 0x49,     // .

        0x30: 0x0D,     // Tab
        0x31: 0x29,     // Space
        0x32: 0x0E,     // `       ~
        0x33: 0x66,     // Backspace
        //        0x34:
        0x35: 0x76,     // Esc
        //        0x36: E027        // Right Cmd        - flags changed
        //        0x37: E01F        // Left Cmd (Apple) - flags changed
        0x38: 0x12,     // Left Shift       - flags changed
        0x39: 0x58,     // Caps Lock        - flags changed
        0x3A: 0x11,     // Left Option      - flags changed - mapped to Left ALT
        0x3B: 0x14,     // Left Control     - flags changed
        0x3C: 0x59,     // Right Shift      - flags changed
        0x3D: 0xE011,   // Right Option     - flags changed - mapped to Right ALT
        0x3E: 0xE014,   // Right Control
        //        0x3F

        //        0x40
        0x41: 0x71,     // Numeric Keypad .
        //        0x42
        0x43: 0x7C,     // Numeric Keypad *
        //        0x44
        0x45: 0x79,     // Numeric Keypad +
        //        0x46
        0x47: 0x77,     // Numlock (Clear ⌧ button above 7 on the keypad)
        //        0x48
        //        0x49
        //        0x4A
        0x4B: 0xE04A,  // Numeric Keypad /
        0x4C: 0xE05A,  // Numeric Keypad Enter
        //        0x4D
        0x4E: 0x7B,     // Numeric Keypad -
        //        0x4F

        //        0x50
        0x51: 0x55,     // Numeric Keypad = - mapped to '=' key
        0x52: 0x70,     // Numeric Keypad 0
        0x53: 0x69,     // Numeric Keypad 1
        0x54: 0x72,     // Numeric Keypad 2
        0x55: 0x7A,     // Numeric Keypad 3
        0x56: 0x6B,     // Numeric Keypad 4
        0x57: 0x73,     // Numeric Keypad 5
        0x58: 0x74,     // Numeric Keypad 6
        0x59: 0x6C,     // Numeric Keypad 7
        //            0x5A
        0x5B: 0x75,     // Numeric Keypad 8
        0x5C: 0x7D,     // Numeric Keypad 9
        //            0x5D
        //            0x5E
        //            0x5F

        0x60: 0x03,     // F5
        0x61: 0x0B,     // F6
        0x62: 0x83,     // F7
        0x63: 0x04,     // F3
        0x64: 0x0A,     // F8
        0x65: 0x01,     // F9
        //            0x66
        0x67: 0x78,     // F11
        //            0x68
        //            0x69:         // F13 - mapped to PrintScreen / SysRq - Needs special handling
        //            0x6A
        0x6B: 0x7E,     // F14 - mapped to Scroll Lock
        //            0x6C
        0x6D: 0x09,     // F10
        //            0x6E
        0x6F: 0x07,     // F12

        //            0x70
        //            0x71:        F15 - Mapped to Pause / Break - needs special handling
        //            0x72:        Help
        0x73: 0xE06C,   // Home
        0x74: 0xE07D,   // Page Up
        0x75: 0xE071,   // Delete (Below the Help Key)
        0x76: 0x0C,     // F4
        0x77: 0xE069,   // End
        0x78: 0x06,     // F2
        0x79: 0xE07A,   // Page Down
        0x7A: 0x05,     // F1
        0x7B: 0xE06B,   // Left Arrow
        0x7C: 0xE074,   // Right Arrow
        0x7D: 0xE072,   // Down Arrow
        0x7E: 0xE075,   // Up Arrow
    ]


    @discardableResult
    private func sendMakeCodesForKeyCode(_ keyCode: UInt16) -> Bool {
        guard let scanCode = scanCodes2[keyCode] else { return false }
        if scanCode > 0xFF {
            let high = UInt8(scanCode >> 8)
            controller?.addScanCode(high)
        }
        let low = UInt8(truncatingIfNeeded: scanCode)
        controller?.addScanCode(low)
        return true
    }


    @discardableResult
    private func sendBreakCodesForKeyCode(_ keyCode: UInt16) -> Bool {
        guard let scanCode = scanCodes2[keyCode] else { return false }
        if scanCode > 0xFF {
            let high = UInt8(scanCode >> 8)
            controller?.addScanCode(high)
        }
        controller?.addScanCode(0xF0)   // break
        let low = UInt8(truncatingIfNeeded: scanCode)
        controller?.addScanCode(low)
        return true
    }


    override func keyDown(with event: NSEvent) {
        //NSLog("Keydown: \(String(event.keyCode, radix: 16)) modfier flags: \(event.modifierFlags)")
        sendMakeCodesForKeyCode(event.keyCode)
    }


    override func keyUp(with event: NSEvent) {
        //NSLog("Keyup: \(String(event.keyCode, radix: 16)) modfier flags: \(event.modifierFlags)")
        sendBreakCodesForKeyCode(event.keyCode)
    }


    // When a modifier eg 'Left Shift' is pressed the event is seens as 'flagsChanged' with a scan code.
    // When the key is then released, the same event is seen. So the state of each key needs to be tracked
    // to determine if it is a press or a release

    private var capsLock: Bool = false
    private var leftShift: Bool = false
    private var rightShift: Bool = false
    private var leftControl: Bool = false
    private var rightControl: Bool = false
    private var leftOption: Bool = false
    private var rightOption: Bool = false

    override func flagsChanged(with event: NSEvent) {

        guard event.type == .flagsChanged else {
            fatalError("Got a flagsChanged event with a different event type \(event.type), \(event)")
        }

        // .flagsChanged does not tell us if the key was pressed or released so the keyCode needs to be used in conjunction
        // with the flags.
        let flags = event.modifierFlags

        // If the flags.contains for a key type eg .shift is false then use this to resync the flag for the left/right key. Its not granular and only tells us both keys have been released
        // but it is useful enough to resync the flags if they have gotten out of sync
        let makeCode: Bool
        switch event.keyCode {
            case 0x39:  // Caps Lock
                capsLock = flags.contains(.capsLock)
                makeCode = capsLock

            case 0x38: // Left shift
                leftShift.toggle()
                if !flags.contains(.shift) {
                    leftShift = false
                    rightShift = false
                }
                makeCode = leftShift

            case 0x3C: // Right Shift
                rightShift.toggle()
                if !flags.contains(.shift) {
                    rightShift = false
                    leftShift = false
                }
                makeCode = rightShift

            case 0x3B: // Left Control
                leftControl.toggle()
                if !flags.contains(.control) {
                    leftControl = false
                    rightControl = false
                }
                makeCode = leftControl

            case 0x3E: // Left Control
                rightControl.toggle()
                if !flags.contains(.control) {
                    rightControl = false
                    leftControl = false
                }
                makeCode = rightControl

            case 0x3A: // Left Option (Alt)
                leftOption.toggle()
                if !flags.contains(.option) {
                    leftOption = false
                    rightOption = false
                }
                makeCode = leftOption

            case 0x3D: // Right Option (Alt)
                rightOption.toggle()
                if !flags.contains(.option) {
                    rightOption = false
                    leftOption = false
                }
                makeCode = rightOption

            default:
                NSLog("Ignoring flagsChanged for keyCode: \(String(event.keyCode, radix: 16))")
                return

        }

        // Resync all flags if possible
        if !flags.contains(.shift) {
            leftShift = false
            rightShift = false
        }

        if !flags.contains(.control) {
            rightControl = false
            leftControl = false
        }
        if !flags.contains(.option) {
            rightOption = false
            leftOption = false
        }

        //NSLog("keyCode: \(event.keyCode) makeCode: \(makeCode)")
        if makeCode {
            sendMakeCodesForKeyCode(event.keyCode)
        } else {
            sendBreakCodesForKeyCode(event.keyCode)
        }
        //NSLog("modifierKeys: LShift: \(leftShift) RShift: \(rightShift) LControl: \(leftControl) RControl: \(rightControl) LAlt: \(leftOption) RAlt: \(rightOption) caps: \(capsLock)")
    }
}

#endif
