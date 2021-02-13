//
//  floppy.swift
//  FakePC
//
//  Created by Simon Evans on 15/08/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Floppy Disk BIOS interface. Handles INT 13H calls for floppies.
//


import HypervisorKit


func biosCallForFloppy(_ diskFunction: Disk.BIOSFunction, fdc: FDC, drive: Int, vm: VirtualMachine) -> Disk.Status {

    let disk = fdc.disks[drive]!
    let vcpu = vm.vcpus[0]
    let status: Disk.Status
    switch diskFunction {

    case .resetDisk:
        status = disk.setCurrentTrack(0)

    case .getStatus:
        status = Disk.Status(rawValue: BDA().floppyDriveStatus) ?? Disk.Status.invalidMedia
        vcpu.registers.ah = status.rawValue

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
        showRegisters(vcpu)

        if let geometry = fdc.mediaTypeForFormat[drive] {
            let sectorCount = Int(vcpu.registers.al)
            let track = Int(vcpu.registers.ch)
            if track >= geometry.tracksPerHead {
                return .ok
            }
            let head = Int(vcpu.registers.dh)
            logger.debug("Format track, media geometry = \(geometry)")
            logger.debug("Format head:  \(head) track: \(track): sectorCount: \(sectorCount)")
            status = disk.formatTrack(track, head: head, sectorCount: sectorCount)
        } else {
            logger.debug("No geometry set for format of drive \(drive)")
            status = .invalidMedia
        }

    case .formatTrackSetBadSectors:
        status = .invalidCommand

    case .formatDrive:
        status = .invalidCommand

    case .readDriveParameters:
        status = disk.getDriveParameters(vcpu: vcpu)
        if status == .ok {
            vcpu.registers.bl = 04  // drive type
            vcpu.registers.dl = UInt8(fdc.disks.filter { $0 != nil }.count) // drive count
        }

    case .initialiseHDControllerTables:
        status = .invalidCommand

    case .readLongSector:
        status = .invalidCommand

    case .writeLongSector:
        status = .invalidCommand

    case .seekToCylinder:
        status = .invalidCommand

    case .alternateDiskReset:
        status = .invalidCommand

    case .readSectorBuffer:
        status = .invalidCommand

    case .writeSectorBuffer:
        status = .invalidCommand

    case .testForDriveReady:
        status = .invalidCommand

    case .recalibrateDrive:
        status = .invalidCommand

    case .controllerRamDiagnostic:
        status = .invalidCommand

    case .driveDiagnostic:
        status = .invalidCommand

    case .controllerInternalDiagnostic:
        status = .invalidCommand

    case .getDiskType:
        showRegisters(vcpu)
        fatalError("FDC: readDASDType should have been handled earlier")

    case .changeOfDiskStatus:
        // Change line inactive, disk not changed
        if fdc.mediaChanged[drive] == false {
            status = .ok
        } else {
            status = .changeLineActive
        }
        fdc.mediaChanged[drive] = false    // Reset changeline

    case .setDiskTypeForFormat:
        showRegisters(vcpu)
        fdc.diskTypeForFormat[drive] = vcpu.registers.al
        let geometry: Disk.Geometry?
        switch vcpu.registers.al {
            // Note the drive type is ignored, only sectorsPerHead, tracksPerHead is relevant.
        case 0x01: geometry = FDC.floppyGeometries[3]  // 360K disk in 360K drive
        case 0x02: geometry = FDC.floppyGeometries[3]  // 360K disk in 1.2M drive
        case 0x03: geometry = FDC.floppyGeometries[6]  // 1.2M disk in 1.2M dirve
        case 0x04: geometry = FDC.floppyGeometries[8]  // 720 disk in 720K/1.2M dirve
        default:
            logger.debug("FDC: setDiskTypeForFormat no matching format for \(vcpu.registers.al)")
            geometry = nil
        }

        if let newGeometry = geometry {
            logger.debug("FDC: Found matching geometry: \(newGeometry)")
            fdc.mediaTypeForFormat[drive] = newGeometry
            status = .ok
        } else {
            status = .invalidMedia
        }

    case .setMediaTypeForFormat:
        // TODO: Determine why DOS tries to format track 80 (ie 81st track) which always fails
        // Where is it getting 81 tracks from?
        let (tracks, sectorsPerTrack) = Disk.trackAndSectorFrom(cx: vcpu.registers.cx)
        logger.debug("FDC: setMediaTypeForFormat: tracks \(tracks) sectorsPerTrack: \(sectorsPerTrack)")

        fdc.mediaTypeForFormat[drive] = nil
        for geometry in FDC.floppyGeometries {
            // Ignore single sided disks
            if geometry.heads == 2, geometry.tracksPerHead == tracks, geometry.sectorsPerTrack == sectorsPerTrack {
                fdc.mediaTypeForFormat[drive] = geometry
                break
            }
        }
        if let newGeometry = fdc.mediaTypeForFormat[drive] {
            logger.debug("FDC: Found matching geometry \(newGeometry)")
            status = .ok
        } else {
            logger.debug("FDC: setMediaTypeForFormat: cant find matching geometry")
            status = .invalidMedia
        }

    case .parkFixedDiskHeads:
        status = .invalidCommand

    case .formatESDIDriveUnit:
        status = .invalidCommand

    case .checkExtensionsPresent: status = disk.checkExtensionsPresent(vcpu: vcpu)

    case .extendedReadSectors: status = .invalidMedia
    case .extendedWriteSectors: status = .invalidMedia
    case .extendedVerifySectors: status = .invalidMedia
    case .extendedSeek: status = .invalidMedia
    case .extendedGetDriveParameters: status = .invalidMedia

    default:
        status = .invalidCommand
    }

    if status == .invalidCommand {
        logger.debug("FDC: Invalid command: \(diskFunction)")
    } else if status != .ok {
        logger.debug("FD: \(diskFunction) returned status \(status)")
        showRegisters(vcpu)
    }
    return status
}
