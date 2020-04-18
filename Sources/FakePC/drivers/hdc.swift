//
//  hdc.swift
//  FakePC
//
//  Created by Simon Evans on 18/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Hard Drive Controller - handles 2 hard drives
//

import HypervisorKit


final class HDC: ISAIOHardware {

    private let disks: [Disk?]

    // Hard drives are already attached at poweron so need to be passed to init()
    init(disk1: Disk? = nil, disk2: Disk? = nil) {
        disks = [disk1, disk2]
    }


    func insert(disk: Disk, intoDrive drive: Int) throws {
        guard drive < 2 else { throw DiskError.invalidDrive }
        throw DiskError.invalidMedia
    }

    func eject(drive: Int) throws {
        guard drive < 2 else { throw DiskError.invalidDrive }
        throw DiskError.invalidMedia
    }


    func biosCall(_ ax: UInt16, _ vm: VirtualMachine) {
        let vcpu = vm.vcpus[0]
        let drive = Int(vm.vcpus[0].registers.dl & 1)


        if let disk = disks[drive] {
            disk.biosCall(ax, vm)
        } else {
            if vcpu.registers.ah == Disk.BIOSFunction.readDASDType.rawValue {
                vcpu.registers.ah = 0 // Disk not present
                vcpu.registers.rflags.carry = false
            } else {
                vcpu.registers.ah = Disk.Status.undefinedError.rawValue
                vcpu.registers.rflags.carry = true
            }
        }
    }
}
