//
//  bios.swift
//  
//
//  Created by Simon Evans on 27/12/2019.
//

import Foundation
import HypervisorKit


func biosCall(vm: VirtualMachine, subSystem: IOPort, function: UInt16) throws {

    //NSLog("biosCall(0x\(String(subSystem, radix: 16)),0x\(String(function, radix: 16)))")
    switch subSystem {
        case 0xE0: video(function, vm)
        case 0xE1: disk(function, vm)
        case 0xE2: serial(function, vm)
        case 0xE3: systemServices(function, vm)
        case 0xE4: keyboard(function, vm)
        case 0xE5: printer(function, vm)
        case 0xE6: try setupBDA(vm) // setup BIOS Data Area
        default: fatalError("Unhandled BIOS call (0x\(String(subSystem, radix: 16)),0x\(String(function, radix: 16)))")
    }
}

/*
private var bdaRegion: UnsafeMutableRawBufferPointer!
public func setupBDA(_ vm: VirtualMachine) throws {

    let bdaPtr = try vm.memory(at: PhysicalAddress(RawAddress(0x400)), count: 256)
//    bdaRegion = UnsafeMutableRawBufferPointer(start: bdaPtr, count: 256)
    print("bdaPtr: \(bdaPtr)")
    bdaPtr.storeBytes(of: 0, toByteOffset: 0, as: UInt16.self)
    bdaPtr.

    var equipment = BitArray16(0)
    equipment[14...15] = 1  // parallel ports
    equipment[9...11] = 0   // serial ports
    equipment[6...7] = 1    // floppy drives
    equipment[4...5] = 0b11 // video mode = 80x25 monochrome
    equipment[2] = 0        // no PS/2 mouse
    equipment[1] = 1        // math co-processor installed
    equipment[0] = 1        // boot floppy present
    bdaPtr.storeBytes(of: equipment.rawValue, toByteOffset: 0x10, as: UInt16.self)

    // Installed RAM 
    bdaPtr.unalignedStoreBytes(of: 640, toByteOffset: 0x13, as: UInt16.self)

    diskInit()
}
*/


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

    fatalError("SERIAL: \(serialFunction) for port \(serialPort) not implemented")
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
    let al = vcpu.registers.al

    let printer = Int(dl)
    guard printer == 0 else {
        fatalError("PRINTER: invalid device: \(printer)")
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
