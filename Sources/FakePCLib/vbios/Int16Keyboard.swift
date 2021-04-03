//
//  Int16Keyboard.swift
//  FakePC
//
//  Created by Simon Evans on 31/03/2021.
//  Copyright © 2021 Simon Evans. All rights reserved.
//
//  INT 16h BIOS Interface
//

import HypervisorKit

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


    func biosCall(function: UInt8, registers: VirtualMachine.VCPU.Registers, _ vm: VirtualMachine) {

        guard let keyboardFunction = BIOSFunction(rawValue: function) else {
            logger.debug("KEYBOARD: AX=0x\(String(registers.ax, radix: 16)) not implemented")
            registers.rflags.zero = false
            registers.rflags.carry = true
            return
        }
        logger.trace("KEYBOARD: \(keyboardFunction)")
        switch keyboardFunction {
            case .waitForKeyAndRead, .extendedWaitForKeyAndRead:
                registers.ax = keyboardBuffer.waitForData()
                registers.rflags.zero = false

            case .getKeyStatus, .extendedGetKeyStatus:
                if let data = keyboardBuffer.peek() {
                    registers.ax = data
                    registers.rflags.zero = false
                } else {
                    registers.ax = 0
                    registers.rflags.zero = true
                }

            case .extendedGetShiftStatus:
                let bda = BDA()
                registers.ah = bda.keyboardStatusFlags2
                fallthrough

            case .getShiftStatus:
                let bda = BDA()
                registers.al = bda.keyboardStatusFlags1
                registers.rflags.zero = false

            default:
                logger.debug("KEYBOARD: \(keyboardFunction) not implemented")
                registers.rflags.zero = false
                registers.rflags.carry = true
        }
    }
}
