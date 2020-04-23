//
//  i8042.swift
//  FakePC
//
//  Created by Simon Evans on 17/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  8042 PS/2 Keyboard and Mouse controller and BIOS INT 16h calls.
//

import Foundation
import HypervisorKit


protocol PS2Device {
    func setController(_ controller: I8042)
}


final class I8042: ISAIOHardware {

    // With no modifiers.
    private let unshiftedMap: [UInt8: UInt16] = [
        0x1C: 0x1E61,   // A
        0x32: 0x3062,   // B
        0x21: 0x2E63,   // C
        0x23: 0x2064,   // D
        0x24: 0x1265,   // E
        0x2B: 0x2166,   // F
        0x34: 0x2267,   // G
        0x33: 0x2368,   // H
        0x43: 0x1769,   // I
        0x3B: 0x246A,   // J
        0x42: 0x256B,   // K
        0x4B: 0x266C,   // L
        0x3A: 0x326D,   // M
        0x31: 0x316E,   // N
        0x44: 0x186F,   // O
        0x4D: 0x1970,   // P
        0x15: 0x1071,   // Q
        0x2D: 0x1372,   // R
        0x1B: 0x1F73,   // S
        0x2C: 0x1474,   // T
        0x3C: 0x1675,   // U
        0x2A: 0x2F76,   // V
        0x1D: 0x1177,   // W
        0x22: 0x2D78,   // X
        0x35: 0x1579,   // Y
        0x1A: 0x2C7A,   // Z

        0x16: 0x0231,   // 1
        0x1E: 0x0332,   // 2
        0x26: 0x0433,   // 3
        0x25: 0x0534,   // 4
        0x2E: 0x0635,   // 5
        0x36: 0x0736,   // 6
        0x3D: 0x0837,   // 7
        0x3E: 0x0938,   // 8
        0x46: 0x0A39,   // 9
        0x45: 0x0B30,   // 0

        0x4E: 0x0C2D,   // -
        0x55: 0x0D3D,   // =
        0x54: 0x1A5B,   // [
        0x5B: 0x1B5D,   // ]
        0x4C: 0x273B,   // ;
        0x52: 0x2827,   // '
        0x0E: 0x2960,   // `
        0x5D: 0x2B5C,   // \
        0x41: 0x332C,   // ,
        0x49: 0x342E,   // .
        0x4A: 0x352F,   // /

        0x05: 0x3B00,   // F1
        0x06: 0x3C00,   // F2
        0x04: 0x3D00,   // F3
        0x0C: 0x3E00,   // F4
        0x03: 0x3F00,   // F5
        0x0B: 0x4000,   // F6
        0x83: 0x4100,   // F7
        0x0A: 0x4200,   // F8
        0x01: 0x4300,   // F9
        0x09: 0x4400,   // F10
        0x78: 0x8500,   // F11
        0x07: 0x8600,   // F12

        0x66: 0x0E08,   // Backspace
        0x5A: 0x1C0D,   // Enter
        0x76: 0x011B,   // Escape
        0x7C: 0x372A,   // Keypad *
        0x7B: 0x4A2D,   // Keypad -
        0x79: 0x4E2B,   // Keypad +
        0x29: 0x3920,   // Spacebar
        0x0D: 0x0F09,   // TAB
    ]

    private let unshiftedE0Map: [UInt8: UInt16] = [
        0x71: 0x5300,   // Delete
        0x72: 0x5000,   // Down Arrow
        0x69: 0x4F00,   // End
        0x6C: 0x4700,   // Home
        0x70: 0x5200,   // Insert
        // Keypad 5
        0x7C: 0x372A,   // Keypad *
        0x4A: 0x352F,   // Keypad /
        0x6B: 0x4B00,   // Left Arrow
        0x7A: 0x5100,   // Page Down
        0x7D: 0x4900,   // Page Up
        0x74: 0x4D00,   // Right Arrow
        0x75: 0x4800,   // Up Arrow
    ]

    // With Shift modifier.
    private let shiftedMap: [UInt8: UInt16] = [
        0x1C: 0x1E41,   // A
        0x32: 0x3042,   // B
        0x21: 0x2E43,   // C
        0x23: 0x2044,   // D
        0x24: 0x1245,   // E
        0x2B: 0x2146,   // F
        0x34: 0x2247,   // G
        0x33: 0x2348,   // H
        0x43: 0x1749,   // I
        0x3B: 0x244A,   // J
        0x42: 0x254B,   // K
        0x4B: 0x264C,   // L
        0x3A: 0x324D,   // M
        0x31: 0x314E,   // N
        0x44: 0x184F,   // O
        0x4D: 0x1950,   // P
        0x15: 0x1051,   // Q
        0x2D: 0x1352,   // R
        0x1B: 0x1F53,   // S
        0x2C: 0x1454,   // T
        0x3C: 0x1655,   // U
        0x2A: 0x2F56,   // V
        0x1D: 0x1157,   // W
        0x22: 0x2D58,   // X
        0x35: 0x1559,   // Y
        0x1A: 0x2C5A,   // Z

        0x16: 0x0221,   // 1
        0x1E: 0x0340,   // 2
        0x26: 0x0423,   // 3
        0x25: 0x0524,   // 4
        0x2E: 0x0625,   // 5
        0x36: 0x075E,   // 6
        0x3D: 0x0826,   // 7
        0x3E: 0x092A,   // 8
        0x46: 0x0A28,   // 9
        0x45: 0x0B29,   // 0

        0x4E: 0x0C5F,   // -
        0x55: 0x0D2B,   // =
        0x54: 0x1A7B,   // [
        0x5B: 0x1B7D,   // ]
        0x4C: 0x273A,   // ;
        0x52: 0x2822,   // '
        0x0E: 0x297E,   // `
        0x5D: 0x2B7C,   // \
        0x41: 0x333C,   // ,
        0x49: 0x343E,   // .
        0x4A: 0x353F,   // /

        0x05: 0x5400,   // F1
        0x06: 0x5500,   // F2
        0x04: 0x5600,   // F3
        0x0C: 0x5700,   // F4
        0x03: 0x5800,   // F5
        0x0B: 0x5900,   // F6
        0x83: 0x5A00,   // F7
        0x0A: 0x5B00,   // F8
        0x01: 0x5C00,   // F9
        0x09: 0x5D00,   // F10
        0x78: 0x8700,   // F11
        0x07: 0x8800,   // F12

        0x66: 0x0E08,   // Backspace
        0x5A: 0x1C0D,   // Enter
        0x76: 0x011B,   // Escape
        //       0x7C: 0x372A,   // Keypad *
        0x7B: 0x4A2D,   // Keypad -
        0x79: 0x4E2B,   // Keypad +
        0x29: 0x3920,   // Spacebar
        0x0D: 0x0F00,   // TAB
    ]

    private let shiftedE0Map: [UInt8: UInt16] = [
        0x71: 0x532E,   // Delete
        0x72: 0x5032,   // Down Arrow
        0x69: 0x4F31,   // End
        0x6C: 0x4737,   // Home
        0x70: 0x5230,   // Insert
        //Keypad 5
        //0x7C: 0x372A,   // Keypad *
        0x4A: 0x352F,   // Keypad /
        0x6B: 0x4B34,   // Left Arrow
        0x7A: 0x5133,   // Page Down
        0x7D: 0x4939,   // Page Up
        0x74: 0x4D36,   // Right Arrow
        0x75: 0x4838,   // Up Arrow
    ]

    // With Control modifier.
    private let controlMap: [UInt8: UInt16] = [
        0x1C: 0x1E01,   // A
        0x32: 0x3002,   // B
        0x21: 0x2E03,   // C
        0x23: 0x2004,   // D
        0x24: 0x1205,   // E
        0x2B: 0x2106,   // F
        0x34: 0x2207,   // G
        0x33: 0x2308,   // H
        0x43: 0x1709,   // I
        0x3B: 0x240A,   // J
        0x42: 0x250B,   // K
        0x4B: 0x260C,   // L
        0x3A: 0x320D,   // M
        0x31: 0x310E,   // N
        0x44: 0x180F,   // O
        0x4D: 0x1910,   // P
        0x15: 0x1011,   // Q
        0x2D: 0x1312,   // R
        0x1B: 0x1F13,   // S
        0x2C: 0x1414,   // T
        0x3C: 0x1615,   // U
        0x2A: 0x2F16,   // V
        0x1D: 0x1117,   // W
        0x22: 0x2D18,   // X
        0x35: 0x1519,   // Y
        0x1A: 0x2C1A,   // Z

//      0x16: 0x0221,   // 1
        0x1E: 0x0340,   // 2
//      0x26: 0x0423,   // 3
//      0x25: 0x0524,   // 4
//      0x2E: 0x0625,   // 5
        0x36: 0x075E,   // 6
//      0x3D: 0x0826,   // 7
//      0x3E: 0x092A,   // 8
//      0x46: 0x0A28,   // 9
//      0x45: 0x0B29,   // 0

        0x4E: 0x0C1F,   // -
//      0x55: 0x0D2B,   // =
        0x54: 0x1A1B,   // [
        0x5B: 0x1B1D,   // ]
//      0x4C: 0x273A,   // ;
//      0x52: 0x2822,   // '
//      0x0E: 0x297E,   // `
        0x5D: 0x2B1C,   // \
//      0x41: 0x333C,   // ,
//      0x49: 0x343E,   // .
//      0x4A: 0x353F,   // /

        0x05: 0x5E00,   // F1
        0x06: 0x5F00,   // F2
        0x04: 0x6000,   // F3
        0x0C: 0x6100,   // F4
        0x03: 0x6200,   // F5
        0x0B: 0x6300,   // F6
        0x83: 0x6400,   // F7
        0x0A: 0x6500,   // F8
        0x01: 0x6600,   // F9
        0x09: 0x6700,   // F10
        0x78: 0x8900,   // F11
        0x07: 0x9000,   // F12

        0x66: 0x0E7F,   // Backspace
        0x5A: 0x1C0A,   // Enter
        0x76: 0x011B,   // Escape
        0x7C: 0x9600,   // Keypad *
        0x7B: 0x8E00,   // Keypad -
//        0x79: 0x4E2B,   // Keypad +
        0x29: 0x3920,   // Spacebar
        0x0D: 0x9400,   // TAB
    ]

    private let controlE0Map: [UInt8: UInt16] = [
        0x71: 0x9300,   // Delete
        0x72: 0x9100,   // Down Arrow
        0x69: 0x7500,   // End
        0x6C: 0x7700,   // Home
        0x70: 0x9200,   // Insert
        //Keypad 5
        //0x7C: 0x372A,   // Keypad *
        0x4A: 0x9500,   // Keypad /
        0x6B: 0x7300,   // Left Arrow
        0x7A: 0x7600,   // Page Down
        0x7D: 0x8400,   // Page Up
        0x74: 0x7400,   // Right Arrow
        0x75: 0x8D00,   // Up Arrow
    ]

    // With ALT modifier.
    private let altMap: [UInt8: UInt16] = [
        0x1C: 0x1E00,   // A
        0x32: 0x3000,   // B
        0x21: 0x2E00,   // C
        0x23: 0x2000,   // D
        0x24: 0x1200,   // E
        0x2B: 0x2100,   // F
        0x34: 0x2200,   // G
        0x33: 0x2300,   // H
        0x43: 0x1700,   // I
        0x3B: 0x2400,   // J
        0x42: 0x2500,   // K
        0x4B: 0x2600,   // L
        0x3A: 0x3200,   // M
        0x31: 0x3100,   // N
        0x44: 0x1800,   // O
        0x4D: 0x1900,   // P
        0x15: 0x1000,   // Q
        0x2D: 0x1300,   // R
        0x1B: 0x1F00,   // S
        0x2C: 0x1400,   // T
        0x3C: 0x1600,   // U
        0x2A: 0x2F00,   // V
        0x1D: 0x1100,   // W
        0x22: 0x2D00,   // X
        0x35: 0x1500,   // Y
        0x1A: 0x2C00,   // Z

        0x16: 0x7800,   // 1
        0x1E: 0x7900,   // 2
        0x26: 0x7A00,   // 3
        0x25: 0x7B00,   // 4
        0x2E: 0x7C00,   // 5
        0x36: 0x7D00,   // 6
        0x3D: 0x7E00,   // 7
        0x3E: 0x7F00,   // 8
        0x46: 0x8000,   // 9
        0x45: 0x8100,   // 0

        0x4E: 0x8200,   // -
        0x55: 0x8300,   // =
        0x54: 0x1A00,   // [
        0x5B: 0x1B00,   // ]
        0x4C: 0x2700,   // ;
//        0x52: 0x2822,   // '
//        0x0E: 0x297E,   // `
        0x5D: 0x2600,   // \
//        0x41: 0x333C,   // ,
//        0x49: 0x343E,   // .
//        0x4A: 0x353F,   // /

        0x05: 0x6800,   // F1
        0x06: 0x6900,   // F2
        0x04: 0x6A00,   // F3
        0x0C: 0x6B00,   // F4
        0x03: 0x6C00,   // F5
        0x0B: 0x6D00,   // F6
        0x83: 0x6E00,   // F7
        0x0A: 0x6F00,   // F8
        0x01: 0x7000,   // F9
        0x09: 0x7100,   // F10
        0x78: 0x8B00,   // F11
        0x07: 0x8C00,   // F12

        0x66: 0x0E00,   // Backspace
        0x5A: 0xA600,   // Enter
        0x76: 0x0100,   // Escape
        0x7C: 0x3700,   // Keypad *
        0x7B: 0x4A00,   // Keypad -
        0x79: 0x4E00,   // Keypad +
        0x29: 0x3920,   // Spacebar
        0x0D: 0xA500,   // TAB
    ]

    private let altE0Map: [UInt8: UInt16] = [
        0x71: 0xA300,   // Delete
        0x72: 0xA000,   // Down Arrow
        0x69: 0x9F00,   // End
        0x6C: 0x9700,   // Home
        0x70: 0xA200,   // Insert
        //Keypad 5
        //0x7C: 0x372A,   // Keypad *
        0x4A: 0xA400,   // Keypad /
        0x6B: 0x9B00,   // Left Arrow
        0x7A: 0xA100,   // Page Down
        0x7D: 0x9900,   // Page Up
        0x74: 0x9D00,   // Right Arrow
        0x75: 0x9800,   // Up Arrow
    ]

    private struct PortBuffer {
        private let lock = NSLock()
        private var semaphore = DispatchSemaphore(value: 0)
        private var buffer: [UInt16] = []

        func peek() -> UInt16? {
            var result: UInt16? = nil
            lock.lock()
            if buffer.count > 0 { result = buffer[0] }
            lock.unlock()
            return result
        }

        mutating func waitForData() -> UInt16 {
            while true {
                lock.lock()
                if buffer.count > 0 {
                    let result = buffer.remove(at: 0)
                    lock.unlock()
                    return result
                }
                lock.unlock()
                semaphore.wait()
            }
        }

        @discardableResult
        mutating func addData(_ data: UInt16) -> Bool {
            var result = false
            lock.lock()
            if buffer.count < 16 {
                buffer.append(data)
                result = true
            } else {
                print("Buffer full!")
            }
            lock.unlock()
            semaphore.signal()
            return result
        }
    }


    private let keyboard: PS2Device?
    private let mouse: PS2Device?
    private var keyboardBuffer: PortBuffer
    private var mouseBuffer: PortBuffer


    init(keyboard: PS2Device? = nil, mouse: PS2Device? = nil) {
        self.keyboard = keyboard
        self.mouse = mouse
        self.keyboardBuffer = PortBuffer()
        self.mouseBuffer = PortBuffer()

        keyboard?.setController(self)
        mouse?.setController(self)
    }


    private var isBreak = false
    private var isE0 = false


    // This is effectively the IRQ1 (INT9) keyboard handler running each time a scancode is sent from the keyboard.
    func addScanCode(_ code: UInt8) {
        //print("addScanCode: \(String(code, radix: 16))")
        if code == 0xF0 {
            isBreak = true
        } else if code == 0xE0 {
            isE0 = true
            isBreak = false
        } else {

            // Check for modifier keys
            var bda = BDA()
            switch code {
                // LShift
                case 0x12: if !isE0 {
                    bda.keyboardStatusFlags1Flags.leftShiftKeyDown = !isBreak
                }

                // RShift
                case 0x59: if !isE0 {
                    bda.keyboardStatusFlags1Flags.rightShiftKeyDown = !isBreak
                }

                // Control
                case 0x14:
                    if !isE0 {  // Left Control
                        bda.keyboardStatusFlags2Flags.leftControlKeyDown = !isBreak
                    } else { // Right Control
                        bda.keyboardStatusFlags3Flags.rightControlKeyDown = !isBreak
                    }
                    bda.keyboardStatusFlags1Flags.controlKeyDown =
                        bda.keyboardStatusFlags2Flags.leftControlKeyDown || bda.keyboardStatusFlags3Flags.rightControlKeyDown


                // Alt
                case 0x11:
                    if !isE0 {  // Left Alt
                        bda.keyboardStatusFlags2Flags.leftAltKeyDown = !isBreak
                    } else {
                        bda.keyboardStatusFlags3Flags.rightAltKeyDown = !isBreak
                    }
                    bda.keyboardStatusFlags1Flags.altKeyDown =
                        bda.keyboardStatusFlags2Flags.leftAltKeyDown || bda.keyboardStatusFlags3Flags.rightAltKeyDown

                // Caps Lock
                case 0x58:
                    if !isE0 {
                        bda.keyboardStatusFlags2Flags.capsLockLeyDown = !isBreak
                        if isBreak {
                            bda.keyboardStatusFlags1Flags.capsLockOn.toggle()
                        }
                    }

                // Scroll Lock
                case 0x7E:
                    if !isE0 {
                        bda.keyboardStatusFlags2Flags.scrollLockKeyDown = !isBreak
                        if isBreak {
                            bda.keyboardStatusFlags1Flags.scrollLockOn.toggle()
                        }
                    }

                // Numlock
                case 0x77:
                    if !isE0 {
                        bda.keyboardStatusFlags2Flags.numLockKeyDown = !isBreak
                        if isBreak {
                            bda.keyboardStatusFlags1Flags.numLockOn.toggle()
                        }
                    }

                default:
                    if !isBreak {
                        let shift = bda.keyboardStatusFlags1Flags.leftShiftKeyDown || bda.keyboardStatusFlags1Flags.rightShiftKeyDown
                        let control = bda.keyboardStatusFlags1Flags.controlKeyDown
                        let alt = bda.keyboardStatusFlags1Flags.altKeyDown

                        //print("isE0: \(isE0)  shift: \(shift)  control: \(control)  alt: \(alt)")
                        let scanCode: UInt16?
                        switch (isE0, shift, control, alt) {
                            case (false, false, false, false):  scanCode = unshiftedMap[code]
                            case (false, true, _, _):           scanCode = shiftedMap[code]
                            case (false, false, true, _):       scanCode = controlMap[code]
                            case (false, false, false, true):   scanCode = altMap[code]

                            case (true, false, false, false):   scanCode = unshiftedE0Map[code]
                            case (true, true, _, _):            scanCode = shiftedE0Map[code]
                            case (true, false, true, _):        scanCode = controlE0Map[code]
                            case (true, false, false, true):    scanCode = altE0Map[code]
                        }

                        if let scanCode = scanCode {
                            //print("adding scanCode: \(String(scanCode, radix: 16))")
                            keyboardBuffer.addData(scanCode)
                        }
                }
            }
            isE0 = false
            isBreak = false
        }
    }
}


// INT 16h BIOS Interface
extension I8042 {

    private enum BIOSFunction: UInt8 {
        case waitForKeyAndRead = 0
        case getKeyStatus = 1
        case getShiftStatus = 2
        case setTypematicRate = 3
        case setKeyclick = 4
        case keyBufferWrite = 5
        case extendedWaitForKeyAndRead = 0x10
        case extendedGetKeyStatus = 0x11
        case extendedGetShiftStatus = 0x12
    }


    func biosCall(_ ax: UInt16, _ vm: VirtualMachine) {
        let function = UInt8(ax >> 8)
        let vcpu = vm.vcpus[0]

        guard let keyboardFunction = BIOSFunction(rawValue: function) else {
            fatalError("KEYBOARD: unknown function 0x\(String(function, radix: 16))")
        }

        switch keyboardFunction {
            case .waitForKeyAndRead, .extendedWaitForKeyAndRead:
                vcpu.registers.ax = keyboardBuffer.waitForData()
                vcpu.registers.rflags.zero = false

            case .getKeyStatus, .extendedGetKeyStatus:
                if let data = keyboardBuffer.peek() {
                    vcpu.registers.ax = data
                    vcpu.registers.rflags.zero = false
                } else {
                    vcpu.registers.ax = 0
                    vcpu.registers.rflags.zero = true
                }

            case .extendedGetShiftStatus:
                let bda = BDA()
                vcpu.registers.ah = bda.keyboardStatusFlags2
                fallthrough

            case .getShiftStatus:
                let bda = BDA()
                vcpu.registers.al = bda.keyboardStatusFlags1
                vcpu.registers.rflags.zero = false

            default:
                print("KEYBOARD: \(keyboardFunction) not implemented")
                vcpu.registers.rflags.zero = false
                vcpu.registers.rflags.carry = true
        }
    }
}
