//
//  bios.swift
//  FakePC
//
//  Created by Simon Evans on 27/12/2019.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  BIOS helper functions, implements some BIOS functionality using para-virtualisation.
//

import Foundation
import HypervisorKit


// The BIOS ROM can make calls using OUT port, AX where port is 0xE0 to 0xEF
func biosCall(vm: VirtualMachine, subSystem: IOPort, function: UInt16) throws {

    //NSLog("biosCall(0x\(String(subSystem, radix: 16)),0x\(String(function, radix: 16)))")
    switch subSystem {
        case 0xE0: if let video = ISA.video { video.biosCall(function, vm) }
        case 0xE1: disk(function, vm)
        case 0xE2: serial(function, vm)
        case 0xE3: systemServices(function, vm)
        case 0xE4: if let keyboardController = ISA.keyboardController { keyboardController.biosCall(function, vm) }
        case 0xE5: printer(function, vm)
        case 0xE6: break //try setupBDA(vm) // setup BIOS Data Area
        case 0xE8: if let rtc = ISA.rtc { rtc.biosCall(function, vm) }
        case 0xEF: debug(function, vm)
        default: fatalError("Unhandled BIOS call (0x\(String(subSystem, radix: 16)),0x\(String(function, radix: 16)))")
    }
}


private func debug(_ ax: UInt16, _ vm: VirtualMachine) {
    print("BIOS Debug call")
    let bda = BDA()
    showRegisters(vm.vcpus[0])
    switch ax {
        case 0x01: print("Entering IRQ0: bda.timerCount:", bda.timerCount)
        case 0x02: print("Exiting IRQ0: bda.timerCount:", bda.timerCount)
        case 0x03: print("Entering INT16")
        case 0x04: print("Exiting INT16")
        default: fatalError("Unhandled DEBUG call \(String(ax, radix: 16))")
    }
}


// INT 0x14
private func serial(_ ax: UInt16, _ vm: VirtualMachine) {
    let function = UInt8(ax >> 8)

    enum SerialFunctions: UInt8 {
        case initialisePort = 0
        case sendCharacter = 1
        case receiveCharacter = 2
        case getPortStatus = 3
        case extendedInitialise = 4
        case extendedPortControl = 5
    }

    guard let serialFunction = SerialFunctions(rawValue: function) else {
        fatalError("SERIAL: function = 0x\(String(function, radix: 16)) not implemented")
    }

    let vcpu = vm.vcpus[0]
    let dl = vcpu.registers.dl
    //    let al = vcpu.registers.al

    let serialPort = Int(dl)

    print("SERIAL: \(serialFunction) for port \(serialPort) not implemented")
    vcpu.registers.rflags.carry = true
}

// INT 0x15
private func systemServices(_ ax: UInt16, _ vm: VirtualMachine) {
    let function = UInt8(ax >> 8)
    let vcpu = vm.vcpus[0]
    showRegisters(vcpu)
    print("SYSTEM: function = 0x\(String(function, radix: 16)) not implemented")
    vcpu.registers.rflags.carry = true

}

// INT 0x17
private func printer(_ ax: UInt16, _ vm: VirtualMachine) {
    let function = UInt8(ax >> 8)

    enum PrinterFunctions: UInt8 {
        case printCharacter = 0
        case initialisePort = 1
        case readPortStatus = 2
    }

    guard let printerFunction = PrinterFunctions(rawValue: function) else {
        fatalError("PRINTER: function = 0x\(String(function, radix: 16)) not implemented")
    }

    let vcpu = vm.vcpus[0]
    let dl = vcpu.registers.dl
    //    let al = vcpu.registers.al

    let printer = Int(dl)
    guard printer == 0 else {
        print("PRINTER: invalid device: \(printer)")
        vcpu.registers.rflags.carry = true
        return
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


