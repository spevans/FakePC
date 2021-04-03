//
//  cdrom.swift
//  FakePC
//
//  Created by Simon Evans on 15/08/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  CDROM BIOS interface. Handles INT 13H calls for CDROMs.
//


import HypervisorKit


func biosCallForCdrom(_ diskFunction: Disk.BIOSFunction, disk: Disk, vm: VirtualMachine) -> Disk.Status {

    logger.debug("CDROM: \(diskFunction)")
    let vcpu = vm.vcpus[0]

    let status: Disk.Status
    switch diskFunction {
        case .resetDisk:
            status = .ok

        case .getStatus:  // Shouldnt be used as dealt with by called
            let statusByte = BDA().statusLastHardDiskOperation
            vcpu.registers.ah = statusByte
            status = Disk.Status(rawValue: statusByte) ?? .undefinedError

        case .readDriveParameters:
            status = .invalidMedia

        case .checkExtensionsPresent:
            status = disk.checkExtensionsPresent(vcpu: vcpu)

        case .extendedReadSectors:
            let dapOffset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
            status = disk.extendedRead(vm: vm, dapOffset: dapOffset)

        case .extendedWriteSectors:
            status = .writeProtected

        case .extendedVerifySectors:
            let dapOffset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
            status = disk.extendedVerify(vm: vm, dapOffset: dapOffset)

        case .lockUnlockDrive:
            status = .invalidCommand

        case .ejectMedia:
            status = .invalidCommand

        case .extendedSeek:
            status = .invalidCommand

        case .extendedGetDriveParameters:
            let dapOffset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
            status = disk.extendedGetDriveParameters(vm: vm, dapOffset: dapOffset)

        case .extendedMediaChange:
            status = .invalidCommand

        case .initiateDiskEmulationForCdrom:
            status = .invalidCommand

        case .terminateDiskEmulationForCdrom:
            status = .invalidCommand

        case .initiateDiskEmulateForCdromAndBoot:
            status = .invalidCommand

        case .returnBootCatalogForCdrom:
            status = .invalidCommand

        case .sendPacketCommand:
            status = .invalidCommand

        default:
            status = .invalidCommand
    }
    /*
     if status == .invalidCommand {
     logger.debug("CDROM: Invalid command: \(diskFunction)")
     } else if status != .ok {
     logger.debug("CDROM: \(diskFunction) returned status \(status)")
     vcpu.showRegisters()
     }
     */
    logger.debug("CDROM: \(diskFunction) returned status \(status)")
    return status
}
