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
        let vcpu = try vm.addVCPU()

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
            try! vcpu.start()
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
                    let registers = try vcpu.readRegisters([.rip, .cs])
                    let ip = UInt64(registers.cs.base) + registers.rip
                    // Is call from BIOS?
                    if (port >= 0xE0 && port <= 0xEF) && (ip >= 0xFE000 && ip <= 0xFFFFF) {
                        // function = AH
                        try biosCall(fakePC: self, subSystem: port, function: UInt8(value >> 8))
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

            case .exception(let exceptionInfo):
                let registers = try vcpu.readRegisters([.rip, .cs])
                vcpu.showRegisters()
                let offset = Int(registers.cs.base) + Int(registers.ip)
                logger.debug("\(vm.memoryRegions[0].dumpMemory(at: offset, count: 16))")
                fatalError("\(vmExit): \(exceptionInfo)")

            case .debug(let debug):
                vcpu.showRegisters()
                fatalError("\(vmExit): \(debug)")

            case .hlt:
                // TODO - Add option to tell hvkit not to return this option
                return false

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

        let registers: Registers
        do {
            registers = try self.readRegisters([.rax, .rbx, .rcx, .rdx, .rdi, .rsi, .rbp, .rsp, .rip, .segmentRegisters, .rflags])
        } catch {
            logger.error("Cannot read registers: \(error)")
            return
        }

        var output = ""

        func showReg(_ name: String, _ value: UInt16) {
            let w = hexNum(value)
            output += "\(name): \(w) "
        }

        showReg("CS", registers.cs.selector)
        showReg("SS", registers.ss.selector)
        showReg("DS", registers.ds.selector)
        showReg("ES", registers.es.selector)
        showReg("FS", registers.fs.selector)
        showReg("GS", registers.gs.selector)
        logger.debug("\(output)")
        output = "FLAGS \(registers.rflags)"
        showReg("IP", registers.ip)
        showReg("AX", registers.ax)
        showReg("BX", registers.bx)
        showReg("CX", registers.cx)
        showReg("DX", registers.dx)
        showReg("DI", registers.di)
        showReg("SI", registers.si)
        showReg("BP", registers.bp)
        showReg("SP", registers.sp)
        logger.debug("\(output)")
    }
}
