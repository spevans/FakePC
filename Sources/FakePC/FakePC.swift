//
//  FakePC.swift
//  FakePC
//
//  Created by Simon Evans on 29/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  BIOS helper functions, implements some BIOS functionality using para-virtualisation.
//

import HypervisorKit
import Foundation
import BABAB


final class FakePC {
    let vm: VirtualMachine
    let ram: MemoryRegion
    let hma: MemoryRegion
    let biosRegion: MemoryRegion
    let rootResourceManager: ResourceManager
    let isa: ISA
    let config: MachineConfig

    private var vmThread: Thread!
    private(set) var vmExitCount = UInt64(0)


    init(config: MachineConfig) throws {
        self.config = config
        vm = try VirtualMachine(logger: logger)
        rootResourceManager = ResourceManager(portRange: IOPort.min...IOPort.max, irqRange: 0...15)
        let vcpu = try vm.createVCPU(startup: { $0.setupRealMode() })

        // Currently only KVM will emulate an PIC and PIT, HVF will not. The PIC/PIT code needs to be added into
        // HypervisorKit then it can be enabled there for HVF and the KVM one used on Linux.
        // try vm.addPICandPIT()
        ram = try vm.addMemory(at: 0, size: 0xA0_000) // 640K RAM everything above is Video RAM and ROM
        hma = try vm.addMemory(at: 0x100_000, size: 0x10_000) // HMA 64KB ram at 1MB mark

        let biosRomSize: UInt64 = 0x40000   // 256K
        biosRegion = try vm.addMemory(at: 0xC0000, size: biosRomSize, readOnly: true)
        // Load BIOS Image into top of ROM
        let biosImage = try Data(contentsOf: config.biosURL)
        let loadAddress = biosRomSize - UInt64(biosImage.count)
        logger.info("BIOS image size 0x\(String(biosImage.count, radix: 16)) load address: 0x\(String(loadAddress, radix: 16))")
        try biosRegion.loadBinary(from: biosImage, atOffset: loadAddress)
        isa = try ISA(config: config, vm: vm, rootResourceManager: rootResourceManager)
        vcpu.vmExitHandler = processVMExit
    }


    func runVMThread() {
        vmThread = Thread {

            let group = DispatchGroup()
            group.enter()
            let vcpu = self.vm.vcpus[0]
            vcpu.completionHandler = {
                group.leave()
            }
            vcpu.start()
            logger.debug("Waiting for VCPU to finish")
            group.wait()
            logger.debug("VCPU has finished")
        }
        vmThread.start()
    }


    func processVMExit(_ vcpu: VirtualMachine.VCPU, _ vmExit: VMExit) throws -> Bool {
        vmExitCount += 1

        switch vmExit {
        case .ioOutOperation(let port, let data):
            if case VMExit.DataWrite.word(let value) = data {
                let ip = UInt64(vcpu.registers.cs.base) + vcpu.registers.rip
                // Is call from BIOS?
                if (port >= 0xE0 && port <= 0xEF) && (ip >= 0xFE000 && ip <= 0xFFFFF) {
                    try biosCall(fakePC: self, subSystem: port, function: value)
                    break
                } else {
                    logger.debug("Port: \(String(port, radix: 16)) IP: \(String(ip, radix: 16))")
                    logger.debug("Not a bios call")
                }

            }
            try self.rootResourceManager.ioOut(port: port, dataWrite: data)

        case .ioInOperation(let port, let dataRead):
            let data = self.rootResourceManager.ioIn(port: port, dataRead: dataRead)
            logger.debug("ioIn(0x\(String(port, radix: 16)), \(dataRead) => \(data))")
            vcpu.setIn(data: data)

        case .memoryViolation(let violation):
            if violation.access == .write {
                if violation.guestPhysicalAddress >= PhysicalAddress(UInt(0xf0000))
                && violation.guestPhysicalAddress <= PhysicalAddress(UInt(0xfffff)) {
                    // Ignore writes to the BIOS
                    logger.debug("Skipping BIOS write: \(violation)")
                    try vcpu.skipInstruction()
                } else {
                    vcpu.showRegisters()
                    fatalError("memory violation")
                }
            }
            break

        case .exception(let exceptionInfo):
            vcpu.showRegisters()
            let offset = Int(vcpu.registers.cs.base) + Int(vcpu.registers.ip)
            logger.debug("\(vcpu.vm.memoryRegions[0].dumpMemory(at: offset, count: 16))")
            fatalError("\(vmExit): \(exceptionInfo)")

        case .debug(let debug):
            vcpu.showRegisters()
            fatalError("\(vmExit): \(debug)")

        case .hlt:
            logger.debug("HLT... exiting")
            vcpu.showRegisters()
            return true


        default:
            logger.debug("\(vmExit)")
            vcpu.showRegisters()
            fatalError("Unhandled exit: \(vmExit)")
        }
        self.isa.processHardware()
        return false
    }
}


extension VirtualMachine.VCPU {
    func showRegisters() {
        guard logger.logLevel <= .debug else { return }

        var registers = ""

        func showReg(_ name: String, _ value: UInt16) {
            let w = hexNum(value, width: 4)
            registers += "\(name): \(w) "
        }

        showReg("CS", self.registers.cs.selector)
        showReg("SS", self.registers.ss.selector)
        showReg("DS", self.registers.ds.selector)
        showReg("ES", self.registers.es.selector)
        showReg("FS", self.registers.fs.selector)
        showReg("GS", self.registers.gs.selector)
        logger.debug("\(registers)")
        registers = "FLAGS \(self.registers.rflags)"
        showReg("IP", self.registers.ip)
        showReg("AX", self.registers.ax)
        showReg("BX", self.registers.bx)
        showReg("CX", self.registers.cx)
        showReg("DX", self.registers.dx)
        showReg("DI", self.registers.di)
        showReg("SI", self.registers.si)
        showReg("BP", self.registers.bp)
        showReg("SP", self.registers.sp)
        logger.debug("\(registers)")
    }
}
