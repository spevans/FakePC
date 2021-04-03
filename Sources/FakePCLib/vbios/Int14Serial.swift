//
//  Int14Serial.swift
//  FakePC
//
//  Created by Simon Evans on 31/03/2021.
//  Copyright © 2021 Simon Evans. All rights reserved.
//
//  INT 14h BIOS Serial services.
//

import HypervisorKit

extension Serial {

    private enum BIOSFunction: UInt8 {
        case initialisePort = 0
        case sendCharacter = 1
        case receiveCharacter = 2
        case getPortStatus = 3
        case extendedInitialise = 4
        case extendedPortControl = 5
    }


    func biosCall(function: UInt8, registers: VirtualMachine.VCPU.Registers, _ vm: VirtualMachine) {
        guard let serialFunction = BIOSFunction(rawValue: function) else {
            fatalError("SERIAL: unknown function 0x\(String(function, radix: 16))")
        }

        switch serialFunction {
            case .initialisePort: fallthrough
            case .sendCharacter: fallthrough
            case .receiveCharacter: fallthrough
            case .getPortStatus: fallthrough
            case .extendedInitialise: fallthrough
            case .extendedPortControl: logger.debug("SERIAL: \(serialFunction) not implemented")
        }
        registers.rflags.carry = true
    }
}
