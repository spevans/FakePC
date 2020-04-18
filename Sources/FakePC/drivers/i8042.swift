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

    private let keyboard: PS2Device?
    private let mouse: PS2Device?


    init(keyboard: PS2Device? = nil, mouse: PS2Device? = nil) {
        self.keyboard = keyboard
        self.mouse = mouse

        keyboard?.setController(self)
        mouse?.setController(self)
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
            default:
                print("KEYBOARD: \(keyboardFunction) not implemented")
                vcpu.registers.rflags.zero = false
                vcpu.registers.rflags.carry = true
        }
    }
}
