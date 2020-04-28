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

    // Set default return error flag
    let vcpu = vm.vcpus[0]
    vcpu.registers.rflags.carry = true

    switch subSystem {
        case 0xE0: if let video = ISA.video { video.biosCall(function, vm) }
        case 0xE1: if let drive = ISA.diskDrive(Int(vcpu.registers.dl)) { drive.biosCall(function, vm) }
        case 0xE2: if let serial = ISA.serialPort(Int(vcpu.registers.dx)) { serial.biosCall(function, vm) }
        case 0xE3: systemServices(function, vm)
        case 0xE4: if let keyboardController = ISA.i8042 { keyboardController.biosCall(function, vm) }
        case 0xE5: if let printer = ISA.printerPort(Int(vcpu.registers.dx)) { printer.biosCall(function, vm) }
        case 0xE6: try setupBDA(vm) // setup BIOS Data Area
        case 0xE8: if let rtc = ISA.rtc { rtc.biosCall(function, vm) }
        case 0xEF: debug(function, vm)
        default: fatalError("Unhandled BIOS call (0x\(String(subSystem, radix: 16)),0x\(String(function, radix: 16)))")
    }
}


private func debug(_ ax: UInt16, _ vm: VirtualMachine) {
    debugLog("BIOS Debug call")
    let bda = BDA()
    showRegisters(vm.vcpus[0])
    let ip = vm.vcpus[0].registers.ip
    if ip >= 0xf30a && ip <= 0xf340 {
        return
    }


    switch ax {
        case 0x01: debugLog("Entering IRQ0: bda.timerCount:", bda.timerCount)
        case 0x02: debugLog("Exiting IRQ0: bda.timerCount:", bda.timerCount)
        case 0x03: debugLog("Entering INT16")
        case 0x04: debugLog("Exiting INT16")
        case 0x05: debugLog("Calling INT19")
        case 0x06: debugLog("In INT19")
        default: fatalError("Unhandled DEBUG call \(String(ax, radix: 16))")
    }
}



// INT 0x15
private func systemServices(_ ax: UInt16, _ vm: VirtualMachine) {
    let function = UInt8(ax >> 8)
    let vcpu = vm.vcpus[0]
    showRegisters(vcpu)
    debugLog("SYSTEM: function = 0x\(String(function, radix: 16)) not implemented")
    vcpu.registers.rflags.carry = true
}

