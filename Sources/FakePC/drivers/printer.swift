//
//  printer.swift
//  FakePC
//
//  Created by Simon Evans on 17/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Emulation of a printer port and BIOS INT 17h calls.
//

import HypervisorKit


final class Printer: ISAIOHardware {

    init() {
    }
}


// INT 17h BIOS Interface
extension Printer {

    private enum BIOSFunction: UInt8 {
        case printCharacter = 0
        case initialisePort = 1
        case readPortStatus = 2
    }


    func biosCall(_ ax: UInt16, _ vm: VirtualMachine) {
        let function = UInt8(ax >> 8)
        let vcpu = vm.vcpus[0]

        guard let printerFunction = BIOSFunction(rawValue: function) else {
            fatalError("PRINTER: unknown function 0x\(String(function, radix: 16))")
        }

        let status: UInt8
        switch printerFunction {
            case .printCharacter:
                let char = UnicodeScalar(vcpu.registers.al)
                print("PRINTER: \(char)")
                status = 0b1100_0000

            case .initialisePort:
                print("PRINTER: Init port")
                status = 0b1100_0000

            case .readPortStatus:
                print("PRINTER: Read port status")
                status = 0b1100_0000
        }

        vcpu.registers.ah = status
        vcpu.registers.rflags.carry = false
    }
}
