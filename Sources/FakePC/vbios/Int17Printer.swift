//
//  Int17Printer.swift
//  FakePC
//
//  Created by Simon Evans on 31/03/2021.
//  Copyright © 2021 Simon Evans. All rights reserved.
//
//  INT 17h BIOS Printer serivces.
//

import HypervisorKit

extension Printer {

    private enum BIOSFunction: UInt8 {
        case printCharacter = 0
        case initialisePort = 1
        case readPortStatus = 2
    }


    func biosCall(function: UInt8, registers: VirtualMachine.VCPU.Registers, _ vm: VirtualMachine) {
        guard let printerFunction = BIOSFunction(rawValue: function) else {
            fatalError("PRINTER: unknown function 0x\(String(function, radix: 16))")
        }

        let status: UInt8
        switch printerFunction {
            case .printCharacter:
                let char = UnicodeScalar(registers.al)
                logger.debug("PRINTER: \(char)")
                status = 0b1100_0000

            case .initialisePort:
                logger.debug("PRINTER: Init port")
                status = 0b1100_0000

            case .readPortStatus:
                logger.debug("PRINTER: Read port status")
                status = 0b1100_0000
        }

        registers.ah = status
        registers.rflags.carry = false
    }
}
