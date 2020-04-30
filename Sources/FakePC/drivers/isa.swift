//
//  isa.swift
//  FakePC
//
//  Created by Simon Evans on 12/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  ISA Hardware setup.
//

import HypervisorKit


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


final class ISA {

    // The VPIC consist of the primary and secondary i8259 PICs to make it easier
    // for ISA devices to send an IRQ 0-15 and have it routed to the correct PIC.
    struct VPIC {
        let pic1: PIC
        let pic2: PIC

        func send(irq: Int) {
            if irq < 8 {
                pic1.send(irq: irq)
            }
            else if irq < 15 {
                pic2.send(irq: irq - 8)
            }
            else {
                debugLog("Invalid IRQ: \(irq)")
            }
        }
    }


    let resourceManager: ResourceManager
    let console: Console
    let vpic: VPIC
    let pit: PIT
    let keyboardController: I8042
    let rtc: RTC
    let video: Video
    let floppyDriveControllers: [FDC]
    let hardDriveControllers: [HDC]
    let serialPorts: [Serial]
    let printerPorts: [Printer]

    private unowned let vm: VirtualMachine


    init(config: MachineConfig, vm: VirtualMachine, rootResourceManager: ResourceManager) throws {
        self.vm = vm
        let vcpu = vm.vcpus.first!

        resourceManager = try rootResourceManager.reserve(portRange: 0...0x3ff, irqRange: 0...15)
        self.console = config.textMode ? CursesConsole() : CocoaConsole()

        // ISA bus has a fixed set of hardware at known locations so they
        // are hardcoded here.
        let pic1 = PIC(vcpu: vcpu, master: nil)
        try resourceManager.registerIOPort(ports: 0x20...0x21, pic1)

        let pic2 = PIC(vcpu: vcpu, master: pic1)
        try resourceManager.registerIOPort(ports: 0xA0...0xA1, pic2)
        vpic = VPIC(pic1: pic1, pic2: pic2)

        pit = PIT(vpic: vpic)
        try resourceManager.registerIOPort(ports: 0x40...0x43, pit)

        keyboardController = I8042(keyboard: console.keyboard, mouse: console.mouse)
        try resourceManager.registerIOPort(ports: 0x60...0x60, keyboardController)
        try resourceManager.registerIOPort(ports: 0x64...0x64, keyboardController)

        rtc = RTC()
        try resourceManager.registerIOPort(ports: 0x70...0x71, rtc)

        video = try Video(vm: vm, display: console)
        try resourceManager.registerIOPort(ports: 0x3B0...0x3DF, video)

        let fdc = FDC(disk1: config.fd0, disk2: config.fd1)
        floppyDriveControllers = [fdc]

        hardDriveControllers = []
        serialPorts = []
        printerPorts = []
    }


    func diskDrive(_ drive: Int) -> ISAIOHardware? {
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


    func serialPort(_ port: Int) -> Serial? {
        guard port < serialPorts.count else { return nil }
        return serialPorts[port]
    }


    func printerPort(_ port: Int) -> Printer? {
        guard port < printerPorts.count else { return nil }
        return printerPorts[port]
    }


    func processHardware() {
        pit.process()
        vpic.pic2.process()
        vpic.pic1.process()
    }
}
