//
//  isa.swift
//  FakePC
//
//  Created by Simon Evans on 12/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  ISA Hardware setup and IO port command interface.
//

import HypervisorKit


protocol ISAIOHardware {

    func ioOut(port: IOPort, operation: VMExit.DataWrite) throws
    func ioIn(port: IOPort, operation: VMExit.DataRead) -> VMExit.DataWrite
    func process()
}


extension ISAIOHardware {

    func ioOut(port: IOPort, operation: VMExit.DataWrite) throws {}

    func ioIn(port: IOPort, operation: VMExit.DataRead) -> VMExit.DataWrite {
        return VMExit.DataWrite(bitWidth: operation.bitWidth, value: 0)!
    }

    func process() {}
}


struct ISA {

    // There is only one ISA bus so everything here is static as this
    // represents a singleton.

    static private var console: Console!
    static private var pic1: PIC?
    static private var pic2: PIC?
    static private var pit: PIT?
    static private(set) var rtc: RTC?
    static private(set) var video: Video?
    static private(set) var keyboardController: KeyboardController?

    // Drivers can register ownership of IO ports to handle IN,OUT
    // instructions.
    static private var ioPortHandlers: [IOPort:ISAIOHardware] = [:]


    static func registerHardware(vm: VirtualMachine) throws {

        let vcpu = vm.vcpus.first!
        // ISA bus has a fixed set of hardware at known locations so they
        // are hardcoded here.
        pic1 = PIC(vcpu: vcpu, master: nil)
        pic2 = PIC(vcpu: vcpu, master: pic1!)

        registerIOPort(ports: 0x20...0x21, pic1!)
        registerIOPort(ports: 0xA0...0xA1, pic2!)

        pit = PIT(pic: pic1!)
        registerIOPort(ports: 0x40...0x43, pit!)

        rtc = RTC(pic: pic2!)
        registerIOPort(ports: 0x70...0x71, rtc!)

        let videoRam = try vm.addMemory(at: 0xA0000, size: 0x20000) // 128k VRAM
        video = try Video(vram: videoRam, display: console)

        keyboardController = KeyboardController(pic: pic1!)
    }


    static func registerIOPort(ports: ClosedRange<IOPort>, _ hardware: ISAIOHardware) {
        for port in ports {
            ioPortHandlers[port] = hardware // (outFunction, inFunction)
        }
    }


    static func ioOut(port: IOPort, dataWrite: VMExit.DataWrite) throws {
        print("IO-OUT: \(String(port, radix: 16)):", dataWrite)
        if let hardware = ioPortHandlers[port] {
            try hardware.ioOut(port: port, operation: dataWrite)
        }
    }


    static func ioIn(port: IOPort, dataRead: VMExit.DataRead) -> VMExit.DataWrite {
        print("IO-IN: \(String(port, radix: 16)):", dataRead)
        if let hardware = ioPortHandlers[port] {
            return hardware.ioIn(port: port, operation: dataRead)
        } else {
            return VMExit.DataWrite(bitWidth: dataRead.bitWidth, value: 0)!
        }
    }


    static func processHardware() {
        pit!.process()
        pic2!.process()
        pic1!.process()
    }

    static func setConsole(_ console: Console) {
        self.console = console
    }
}
