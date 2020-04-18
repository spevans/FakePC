//
//  fdc.swift
//  FakePC
//
//  Created by Simon Evans on 18/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Floppy Drive Controller - handles 2 floppy drives
//

import HypervisorKit


final class FDC: ISAIOHardware {

    private var disks: [Disk?] = [nil, nil]

    init(disk1: Disk? = nil, disk2: Disk? = nil) {
        disks = [disk1, disk2]
    }


    func insert(disk: Disk, intoDrive drive: Int) throws {
        guard drive < 2 else { throw DiskError.invalidDrive }
        guard disk.isFloppyDisk else { throw DiskError.invalidMedia }
        disks[drive] = disk
    }

    func eject(drive: Int) throws {
        guard drive < 2 else { throw DiskError.invalidDrive }
        disks[drive] = nil
    }


    func biosCall(_ ax: UInt16, _ vm: VirtualMachine) {
        let vcpu = vm.vcpus[0]
        let drive = Int(vcpu.registers.dl & 1)

        let status: UInt8
        var bda = BDA()

        if let disk = disks[drive] {
            if vcpu.registers.ah == Disk.BIOSFunction.getStatus.rawValue {
                vcpu.registers.ah = bda.floppyDriveStatus
                vcpu.registers.rflags.carry = false
                return
            }
            disk.biosCall(ax, vm)
            status = vcpu.registers.ah
        } else {
            status = Disk.Status.undefinedError.rawValue
            vcpu.registers.rflags.carry = true
        }
        bda.floppyDriveStatus = status
    }
}
