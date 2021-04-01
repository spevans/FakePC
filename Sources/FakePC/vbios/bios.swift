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
func biosCall(fakePC: FakePC, subSystem: IOPort, function: UInt8) throws {
    let vm = fakePC.vm
    let isa = fakePC.isa
    let vcpu = vm.vcpus[0]
    let registers = try vcpu.readRegisters([.rax, .rbx, .rcx, .rdx, .rsi, .rflags, .segmentRegisters])

    logger.debug("biosCall, subSystem: \(String(subSystem, radix: 16)), function: \(String(function, radix: 16))")
    func debug() {
        logger.debug("BIOS Debug call")
        let bda = BDA()
        vcpu.showRegisters()
        let ip = registers.ip
        if ip >= 0xf30a && ip <= 0xf340 {
            return
        }

        let ax = registers.ax
        switch ax {
            case 0x01: logger.debug("Entering IRQ0: bda.timerCount: \(bda.timerCount)")
            case 0x02: logger.debug("Exiting IRQ0: bda.timerCount: \(bda.timerCount)")
            case 0x03: logger.debug("Entering INT16")
            case 0x04: logger.debug("Exiting INT16")
            case 0x05: logger.debug("Calling INT19")
            case 0x06: logger.debug("In INT19")
            default: fatalError("Unhandled DEBUG call \(String(ax, radix: 16))")
        }
    }


    // Set default return error flag
    registers.rflags.carry = true

    switch subSystem {
        case 0xE0: isa.video.biosCall(function: function, registers: registers, vm)
        case 0xE1: diskCall(function: function, vm: vm, isa: isa)
        case 0xE2: if let serial = isa.serialPort(Int(registers.dx)) { serial.biosCall(function: function, registers: registers, vm) }
        case 0xE3: systemServices(function: function, registers: registers, vm)
        case 0xE4: isa.keyboardController.biosCall(function: function, registers: registers, vm)
        case 0xE5: if let printer = isa.printerPort(Int(registers.dx)) { printer.biosCall(function: function, registers: registers, vm) }
        case 0xE6:
            setupDisks(isa)
            try setupBDA(fakePC: fakePC) // setup BIOS Data Area

        case 0xE8: isa.rtc.biosCall(function: function, registers: registers, vm)
        case 0xEF: debug()
        default: fatalError("Unhandled BIOS call (0x\(String(subSystem, radix: 16)),0x\(String(function, radix: 16)))")
    }
}


// INT 0x15
private func systemServices(function: UInt8, registers: VirtualMachine.VCPU.Registers, _ vm: VirtualMachine) {
    let vcpu = vm.vcpus[0]
    vcpu.showRegisters()
    logger.debug("SYSTEM: function = 0x\(String(function, radix: 16)) not implemented")
    registers.rflags.carry = true
}
