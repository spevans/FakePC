//
//  harddisk.swift
//  FakePC
//
//  Created by Simon Evans on 15/08/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Hard Disk BIOS interface. Handles INT 13H calls for hard disks.
//


import HypervisorKit


func biosCallForHardDrive(_ diskFunction: Disk.BIOSFunction, hdc: HDC, drive: Int, vm: VirtualMachine) -> Disk.Status {

    let disk = hdc.disks[drive]!
    let vcpu = vm.vcpus[0]
    let status: Disk.Status
    switch diskFunction {

        case .resetDisk:
            status = disk.setCurrentTrack(0)

        case .getStatus:  // Shouldnt be used as dealt with by called
            let statusByte = BDA().statusLastHardDiskOperation
            vcpu.registers.ah = statusByte
            status = Disk.Status(rawValue: statusByte) ?? .undefinedError

        case .readSectors:
            switch disk.validateSectorOperation(vcpu: vcpu) {
                case .failure(let error):
                    status = error

                case .success(let operation):
                    let ptr = vm.memoryRegions[0].rawBuffer.baseAddress!.advanced(by: operation.bufferOffset)
                    let buffer = UnsafeMutableRawBufferPointer(start: ptr, count: operation.bufferSize)
                    status = operation.readSectors(into: buffer)
            }

        case .writeSectors:
            if disk.isReadOnly {
                status = .writeProtected
                break
            } else {
                switch disk.validateSectorOperation(vcpu: vcpu) {
                    case .failure(let error):
                        status = error

                    case .success(let operation):
                        let ptr = vm.memoryRegions[0].rawBuffer.baseAddress!.advanced(by: operation.bufferOffset)
                        let buffer = UnsafeRawBufferPointer(start: ptr, count: operation.bufferSize)
                        status = operation.writeSectors(from: buffer)
                }
            }

        case .verifySectors:
            switch disk.validateSectorOperation(vcpu: vcpu) {
                case .failure(let error):
                    status = error

                case .success(let operation):
                    let ptr = vm.memoryRegions[0].rawBuffer.baseAddress!.advanced(by: operation.bufferOffset)
                    let buffer = UnsafeRawBufferPointer(start: ptr, count: operation.bufferSize)
                    status = operation.verifySectors(using: buffer)
            }

        case .formatTrack:
            status = .invalidCommand    // Only for floppy drives

        case .formatTrackSetBadSectors:
            status = .invalidCommand

        case .formatDrive:
            status = .invalidCommand

        case .readDriveParameters:
            status = disk.getDriveParameters(vcpu: vcpu)
            if status == .ok {
                vcpu.registers.bl = 00  // drive type
                vcpu.registers.dl = UInt8(hdc.disks.filter { $0 != nil }.count) // drive count
            }

        case .initialiseHDControllerTables:
            status = .invalidCommand

        case .readLongSector:
            status = .invalidCommand

        case .writeLongSector:
            status = .invalidCommand

        case .seekToCylinder:
            let (track, _) = Disk.trackAndSectorFrom(cx: vcpu.registers.cx)
            status = disk.setCurrentTrack(track)

        case .alternateDiskReset:
            // Reset both disks
            let status1 = hdc.disks[0]?.setCurrentTrack(0) ?? .ok
            let status2 = hdc.disks[1]?.setCurrentTrack(0) ?? .ok
            status = (status1 != .ok) ? status1 : status2

        case .readSectorBuffer:
            status = .invalidCommand

        case .writeSectorBuffer:
            status = .invalidCommand

        case .testForDriveReady:
            status = .ok

        case .recalibrateDrive:
            status = disk.setCurrentTrack(0)

        case .controllerRamDiagnostic:
            status = .ok

        case .driveDiagnostic:
            status = .ok

        case .controllerInternalDiagnostic:
            status = .ok

        case .getDiskType:
            fatalError("HDC: readDASDType should have been handled earlier")

        case .changeOfDiskStatus:
            // Change line inactive, disk not changed
            status = .invalidCommand

        case .setDiskTypeForFormat:
            status = .invalidCommand

        case .setMediaTypeForFormat:
            status = .invalidCommand

        case .parkFixedDiskHeads:
            status = disk.setCurrentTrack(0)

        case .formatESDIDriveUnit:
            status = .invalidCommand

        case .checkExtensionsPresent:
            status = disk.checkExtensionsPresent(vcpu: vcpu)

        case .extendedReadSectors:
            let dapOffset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
            status = disk.extendedRead(vm: vm, dapOffset: dapOffset)

        case .extendedWriteSectors:
            let dapOffset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
            status = disk.extendedWrite(vm: vm, dapOffset: dapOffset)

        case .extendedVerifySectors:
            let dapOffset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
            status = disk.extendedVerify(vm: vm, dapOffset: dapOffset)

        case .extendedSeek:
            status = .invalidCommand

        case .extendedGetDriveParameters:
            let dapOffset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
            status = disk.extendedGetDriveParameters(vm: vm, dapOffset: dapOffset)

        default:
            status = .invalidCommand

    }

    if status == .invalidCommand {
        logger.debug("HDC: Invalid command: \(diskFunction)")
    } else if status != .ok {
        logger.debug("HDC: \(diskFunction) returned status \(status)")
        vcpu.showRegisters()
    }
    return status
}
