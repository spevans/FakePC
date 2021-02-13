//
//  serial.swift
//  FakePC
//
//  Created by Simon Evans on 17/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Emulation of a serial port and BIOS INT 14h calls.
//

import Foundation
import HypervisorKit


final class Serial: ISAIOHardware {

    init() {
    }
}


// INT 14h BIOS Interface
extension Serial {

    private enum BIOSFunction: UInt8 {
        case initialisePort = 0
        case sendCharacter = 1
        case receiveCharacter = 2
        case getPortStatus = 3
        case extendedInitialise = 4
        case extendedPortControl = 5
    }


    func biosCall(_ ax: UInt16, _ vm: VirtualMachine) {
        let function = UInt8(ax >> 8)
        let vcpu = vm.vcpus[0]

        guard let serialFunction = BIOSFunction(rawValue: function) else {
            fatalError("SERIAL: unknown function 0x\(String(function, radix: 16))")
        }

        switch serialFunction {
            case .initialisePort:       fallthrough
            case .sendCharacter:        fallthrough
            case .receiveCharacter:     fallthrough
            case .getPortStatus:        fallthrough
            case .extendedInitialise:   fallthrough
            case .extendedPortControl:  logger.debug("SERIAL: \(serialFunction) not implemented")
        }
        vcpu.registers.rflags.carry = true
    }
}
