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
func biosCall(fakePC: FakePC, subSystem: IOPort, function: UInt16) throws {
    let vm = fakePC.vm
    let isa = fakePC.isa
    let vcpu = vm.vcpus[0]

    // Set default return error flag
    vcpu.registers.rflags.carry = true

    switch subSystem {
        case 0xE0: isa.video.biosCall(function, vm)
    case 0xE1: diskCall(function: function, vm: vm, isa: isa)
        case 0xE2: if let serial = isa.serialPort(Int(vcpu.registers.dx)) { serial.biosCall(function, vm) }
        case 0xE3: systemServices(function, vm)
        case 0xE4: isa.keyboardController.biosCall(function, vm)
        case 0xE5: if let printer = isa.printerPort(Int(vcpu.registers.dx)) { printer.biosCall(function, vm) }

        case 0xE6:
            setupDisks(isa)
            try setupBDA(fakePC: fakePC) // setup BIOS Data Area

        case 0xE8: isa.rtc.biosCall(function, vm)
        case 0xEF: debug(function, vm)
        default: fatalError("Unhandled BIOS call (0x\(String(subSystem, radix: 16)),0x\(String(function, radix: 16)))")
    }
}


// Maps BIOS disk number to Disk, 00-7f, floppies 0x80-0xDF hard disk, 0xE0-0xEF CDROM

//
private enum PhysicalMedia {
case fdc(Int)      // channel 0 or 1
case hdc(Int, Int) // controller 0/1, channel 0/1
case cdromEmulatingFloppy(Disk)
case cdromEmulatingHarddisk(Disk)
}

private var disks: [UInt8: PhysicalMedia] = [:]

private func setupDisks(_ isa: ISA) {
    disks[0] = PhysicalMedia.fdc(0)
    disks[1] = PhysicalMedia.fdc(1)

    var hd = UInt8(0x80)
    var cdrom = UInt8(0xE0)

    for (hdcIdx, hdc) in isa.hardDriveControllers.enumerated() {
        for (channel, disk) in hdc.disks.enumerated() {
            guard let disk = disk else { continue }
            if disk.isHardDisk {
                disks[hd] = PhysicalMedia.hdc(hdcIdx, channel)
                hd += 1
            } else if disk.isCdrom {
                disks[cdrom] = PhysicalMedia.hdc(hdcIdx, channel)
                cdrom += 1
            } else {
                fatalError("Disk in HDC \(hdcIdx),\(channel) is not a harddisk or cdrom")
            }
        }
    }
    debugLog("BIOS disk mapping:")
    for key in disks.keys.sorted() {
        debugLog("\(String(key, radix: 16)):", disks[key]!)
    }
}


private func diskCall(function: UInt16, vm: VirtualMachine, isa: ISA) {
    let vcpu = vm.vcpus[0]
    let drive = vcpu.registers.dl

    guard let diskFunction = Disk.BIOSFunction(rawValue: UInt8(function >> 8)) else {
        let status = Disk.Status.invalidCommand
        vcpu.registers.ah = status.rawValue
        vcpu.registers.rflags.carry = true
        if drive < 0x80 {
            var bda = BDA()
            bda.floppyDriveStatus = status.rawValue
        }
        debugLog("DISK: function: 0x\(String(function, radix: 16)) drive = \(String(drive, radix: 16))H not implemented")
        return
    }


    var bda = BDA()
    var status: Disk.Status = .undefinedError

    if let media = disks[drive] {
        switch media {
        case .fdc(let channel):
            let fdc = isa.floppyDriveController
            let disk = fdc.disks[channel]
            if diskFunction == .getDiskType {
                if disk != nil {
                    vcpu.registers.ah = 1   // Floppy without changeline support FIXME
                } else {
                    vcpu.registers.ah = 0   // No such drive
                }
                status = .ok
                vcpu.registers.rflags.carry = false
                return
            } else {
                if disk != nil {
                    status = biosCallForFloppy(diskFunction, fdc: fdc, drive: channel, vm: vm)
                } else {
                    status = .undefinedError
                }
            }
            bda.floppyDriveStatus = status.rawValue

        case .hdc(let controller, let channel):
            let hdc = isa.hardDriveControllers[controller]
            let disk = hdc.disks[channel]
            if diskFunction == .getDiskType {
                if let disk = disk, disk.isHardDisk {
                    vcpu.registers.ah = 3   // Hard Drive
                    let sectors = disk.geometry.totalSectors
                    vcpu.registers.cx = UInt16(sectors >> 16)
                    vcpu.registers.dx = UInt16(truncatingIfNeeded: sectors)
                } else {
                    vcpu.registers.ah = 0   // No such drive - includes cdroms
                }
                status = .ok
                vcpu.registers.rflags.carry = false
                return
            } else {
                if let disk = disk {
                    if disk.isHardDisk {
                        status = biosCallForHardDrive(diskFunction, hdc: hdc, drive: channel, vm: vm)
                    } else {
                        status = biosCallForCdrom(diskFunction, disk: disk, vm: vm)
                    }
                } else {
                    status = .undefinedError
                }
            }
            bda.statusLastHardDiskOperation = status.rawValue

        case .cdromEmulatingFloppy(let cdrom):
            status = biosCallForCdrom(diskFunction, disk: cdrom, vm: vm)
            bda.floppyDriveStatus = status.rawValue

        case .cdromEmulatingHarddisk(let cdrom):
            status = biosCallForCdrom(diskFunction, disk: cdrom, vm: vm)
            bda.statusLastHardDiskOperation = status.rawValue
        }
    }


    if status != .ok {
        debugLog("DISK: command \(diskFunction) from drive \(drive) error: \(status)")
    }

    vcpu.registers.ah = status.rawValue
    vcpu.registers.rflags.carry = (status != .ok)
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
