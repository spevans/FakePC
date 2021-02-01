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

    debugLog("CDROM: \(diskFunction)")
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
                status = disk.extendedRead(vcpu: vcpu)

            case .extendedWriteSectors:
                status = .writeProtected

            case .extendedVerifySectors:
                status = disk.extendedVerify(vcpu: vcpu)

            case .lockUnlockDrive:
                status = .invalidCommand

            case .ejectMedia:
                status = .invalidCommand

            case .extendedSeek:
                status = .invalidCommand

            case .extendedGetDriveParameters:
                status = disk.extendedGetDriveParameters(vcpu: vcpu)

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
            debugLog("CDROM: Invalid command: \(diskFunction)")
        } else if status != .ok {
            debugLog("CDROM: \(diskFunction) returned status \(status)")
            showRegisters(vcpu)
        }
*/
        debugLog("CDROM: \(diskFunction) returned status \(status)")
        return status
    }
