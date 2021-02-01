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
        vm = try VirtualMachine()
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
        debugLog("BIOS image size 0x\(String(biosImage.count, radix: 16)) load address: 0x\(String(loadAddress, radix: 16))")
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
            debugLog("Waiting for VCPU to finish")
            group.wait()
            debugLog("VCPU has finished")
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
                    debugLog("Port: \(String(port, radix: 16)) IP: \(String(ip, radix: 16))")
                    debugLog("Not a bios call")
                }

            }
            try self.rootResourceManager.ioOut(port: port, dataWrite: data)

        case .ioInOperation(let port, let dataRead):
            let data = self.rootResourceManager.ioIn(port: port, dataRead: dataRead)
            debugLog("ioIn(0x\(String(port, radix: 16)), \(dataRead) => \(data))")
            vcpu.setIn(data: data)

        case .memoryViolation(let violation):
            if violation.access == .write {
                if violation.guestPhysicalAddress >= PhysicalAddress(UInt(0xf0000))
                && violation.guestPhysicalAddress <= PhysicalAddress(UInt(0xfffff)) {
                    // Ignore writes to the BIOS
                    debugLog("Skipping BIOS write: \(violation)")
                    try vcpu.skipInstruction()
                } else {
                    showRegisters(vcpu)
                    fatalError("memory violation")
                }
            }
            break

        case .exception(let exceptionInfo):
            showRegisters(vcpu)
            let offset = Int(vcpu.registers.cs.base) + Int(vcpu.registers.ip)
            debugLog(vcpu.vm.memoryRegions[0].dumpMemory(at: offset, count: 16))

            fatalError("\(vmExit): \(exceptionInfo)")

        case .debug(let debug):
            showRegisters(vcpu)
            fatalError("\(vmExit): \(debug)")

        case .hlt:
            debugLog("HLT... exiting")
            showRegisters(vcpu)
            return true


        default:
            debugLog(vmExit)
            showRegisters(vcpu)
            fatalError("Unhandled exit: \(vmExit)")
        }
        self.isa.processHardware()
        return false
    }
}
