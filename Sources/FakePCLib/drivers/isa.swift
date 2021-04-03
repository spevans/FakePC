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
    func biosCall(function: UInt8, registers: VirtualMachine.VCPU.Registers, _ vm: VirtualMachine)
}


extension ISAIOHardware {

    func ioOut(port: IOPort, operation: VMExit.DataWrite) throws {}

    func ioIn(port: IOPort, operation: VMExit.DataRead) -> VMExit.DataWrite {
        return VMExit.DataWrite(bitWidth: operation.bitWidth, value: 0)!
    }

    func process() {}
    func biosCall(function: UInt8, registers: VirtualMachine.VCPU.Registers, _ vm: VirtualMachine) {
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
                logger.debug("Invalid IRQ: \(irq)")
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
    let floppyDriveController: FDC
    let hardDriveControllers: [HDC]
    let serialPorts: [Serial]
    let printerPorts: [Printer]
    let misc: MiscHardware

    private unowned let vm: VirtualMachine


    init(config: MachineConfig, vm: VirtualMachine, rootResourceManager: ResourceManager) throws {
        self.vm = vm
        let vcpu = vm.vcpus.first!

        resourceManager = try rootResourceManager.reserve(portRange: 0...0x3ff, irqRange: 0...15)
        // TODO - Generate list of valid displays for each platform and feed into config parser
        #if os(macOS)
        self.console = config.textMode ? CursesConsole() : CocoaConsole()
        #else
        self.console = CursesConsole()
        #endif
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
        floppyDriveController = fdc

        let hdc = HDC(disk1: config.hd0, disk2: config.hd1)
        hardDriveControllers = [hdc]

        let com1 = Serial(basePort: 0x3f8, irq: 4)
        try resourceManager.registerIOPort(ports: 0x3f8...0x3ff, com1)

        serialPorts = [
            com1
        ]
        printerPorts = []

        misc = MiscHardware()
        try resourceManager.registerIOPort(port: 0x92, misc)
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


final class MiscHardware: ISAIOHardware {

    private var portA: UInt8 = 0

    func ioOut(port: IOPort, operation: VMExit.DataWrite) throws {
        guard case .byte(let byte) = operation else {
            logger.debug("PORTA: Unexpected write of \(operation) to port 0x\(String(port, radix: 16))")
            return
        }

        switch port {
            case 0x92:      // PS/2 system control port A
                portA = byte
                let a20Active = byte & 0x2 == 0x2
                logger.debug("PORTA: A20 enabled: \(a20Active)")

            default: fatalError("PORTA: Unexpected IN port access 0x\(String(port, radix: 16))")
        }

    }


    func ioIn(port: IOPort, operation: VMExit.DataRead) -> VMExit.DataWrite {
        switch port {
            case 0x92:      // PS/2 system control port A
                return .byte(portA)

            default: fatalError("PORTA: Unexpected IN port access 0x\(String(port, radix: 16))")
        }
    }

    func process() {
    }
}
