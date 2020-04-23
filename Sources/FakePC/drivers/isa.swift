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


enum ISAError: Error {
    case IOPortInUse
    case IRQInUse
}


protocol ISAIOHardware {

    func ioOut(port: IOPort, operation: VMExit.DataWrite) throws
    func ioIn(port: IOPort, operation: VMExit.DataRead) -> VMExit.DataWrite
    func process()

    // Some ISA hardware implements BIOS functionality
    func biosCall(_ ax: UInt16, _ vm: VirtualMachine)
}


extension ISAIOHardware {

    func ioOut(port: IOPort, operation: VMExit.DataWrite) throws {}

    func ioIn(port: IOPort, operation: VMExit.DataRead) -> VMExit.DataWrite {
        return VMExit.DataWrite(bitWidth: operation.bitWidth, value: 0)!
    }

    func process() {}
    func biosCall(_ ax: UInt16, _ vm: VirtualMachine) {
        fatalError("\(self) does not implement biosCall()")
    }
}


struct ISA {

    // There is only one ISA bus so everything here is static as this
    // represents a singleton.

    static private var console: Console!
    static private var pic1: PIC?
    static private var pic2: PIC?
    static private var pit: PIT?
    static private(set) var i8042: I8042?
    static private(set) var rtc: RTC?
    static private(set) var video: Video?
    static private var floppyDriveControllers: [FDC] = []
    static private var hardDriveControllers: [HDC] = []
    static private var serialPorts: [Serial] = []
    static private var printerPorts: [Printer] = []

    // Drivers can register ownership of IO ports to handle IN,OUT
    // instructions.
    static private var ioPortHandlers: [IOPort:ISAIOHardware] = [:]


    static func registerHardware(vm: VirtualMachine) throws {

        let vcpu = vm.vcpus.first!
        // ISA bus has a fixed set of hardware at known locations so they
        // are hardcoded here.
        pic1 = PIC(vcpu: vcpu, master: nil)
        try registerIOPort(ports: 0x20...0x21, pic1!)

        pic2 = PIC(vcpu: vcpu, master: pic1!)
        try registerIOPort(ports: 0xA0...0xA1, pic2!)

        pit = PIT()
        try registerIOPort(ports: 0x40...0x43, pit!)

        i8042 = I8042(keyboard: console.keyboard, mouse: console.mouse)
        try registerIOPort(port: 0x60, i8042!)
        try registerIOPort(port: 0x64, i8042!)

        rtc = RTC()
        try registerIOPort(ports: 0x70...0x71, rtc!)

        let videoRam = try vm.addMemory(at: 0xA0000, size: 0x20000) // 128k VRAM
        video = try Video(vram: videoRam, display: console)
        try registerIOPort(ports: 0x3B0...0x3DF, video!)

#if os(Linux)
        let image = "/home/spse/src/osx/FakePC/FD13FLOP.IMG"
#else
        let image = "/Users/spse/Files/src/osx/FakePC/pc-dos.img"
#endif

        guard let disk = Disk(imageName: image) else {
            fatalError("Cant load floppy image")
        }

        let fdc = FDC(disk1: disk)
        floppyDriveControllers.append(fdc)
    }


    static func diskDrive(_ drive: Int) -> ISAIOHardware? {
        // Each controller handles 2 drives
        if drive < 0x80 {
            let fdc = drive >> 1
            if floppyDriveControllers.count > fdc {
                return floppyDriveControllers[fdc]
            }
        } else {
            let hdc = (drive - 0x80) >> 1
            if hardDriveControllers.count > hdc {
                return hardDriveControllers[hdc]
            }
        }
        return nil
    }


    static func serialPort(_ port: Int) -> Serial? {
        guard port < serialPorts.count else { return nil }
        return serialPorts[port]
    }


    static func printerPort(_ port: Int) -> Printer? {
        guard port < printerPorts.count else { return nil }
        return printerPorts[port]
    }


    static func registerIOPort(port: IOPort, _ hardware: ISAIOHardware) throws {
        guard ioPortHandlers[port] == nil else { throw ISAError.IOPortInUse }
        ioPortHandlers[port] = hardware
    }


    static func registerIOPort(ports: ClosedRange<IOPort>, _ hardware: ISAIOHardware) throws {
        for port in ports {
            guard ioPortHandlers[port] == nil else { throw ISAError.IOPortInUse }
        }
        for port in ports {
            ioPortHandlers[port] = hardware
        }
    }


    static func ioOut(port: IOPort, dataWrite: VMExit.DataWrite) throws {
//        print("IO-OUT: \(String(port, radix: 16)):", dataWrite)
        if let hardware = ioPortHandlers[port] {
            try hardware.ioOut(port: port, operation: dataWrite)
        }
    }


    static func ioIn(port: IOPort, dataRead: VMExit.DataRead) -> VMExit.DataWrite {
  //      print("IO-IN: \(String(port, radix: 16)):", dataRead)
        if let hardware = ioPortHandlers[port] {
            return hardware.ioIn(port: port, operation: dataRead)
        } else {
            return VMExit.DataWrite(bitWidth: dataRead.bitWidth, value: 0)!
        }
    }


    static func send(irq: Int) {
        if irq < 8 {
            pic1!.send(irq: irq)
        }
        else if irq < 15 {
            pic2!.send(irq: irq - 8)
        }
        else {
            print("Invalid IRQ: \(irq)")
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
