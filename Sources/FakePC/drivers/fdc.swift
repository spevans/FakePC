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

    struct BiosFloppyType {
        let geometry: Disk.Geometry
    }


    static private let floppyGeometries: [Disk.Geometry] = [
        // 160K 5.25" Single Sided Double Density
        Disk.Geometry(sectorsPerTrack: 8, tracksPerHead: 40, heads: 1),
        // 320K 5.25" Double Sided Double Density
        Disk.Geometry(sectorsPerTrack: 8, tracksPerHead: 40, heads: 2),

        // 180K 5.25" Single Sided Double Density
        Disk.Geometry(sectorsPerTrack: 9, tracksPerHead: 40, heads: 1),
        // 360K 5.25" Double Sided Double Density
        Disk.Geometry(sectorsPerTrack: 9, tracksPerHead: 40, heads: 2),

        // 320K 5.25" & 3.5" Single Sided Quad Density
        Disk.Geometry(sectorsPerTrack: 8, tracksPerHead: 80, heads: 1),
        // 640K 5.25" & 3.5" Double Sided Quad Density
        Disk.Geometry(sectorsPerTrack: 8, tracksPerHead: 80, heads: 2),

        // 1200K 1.2M Double Sided High Density
        Disk.Geometry(sectorsPerTrack: 15, tracksPerHead: 80, heads: 2),

        // 360K 3.5" Single Sided Double Density
        Disk.Geometry(sectorsPerTrack: 9, tracksPerHead: 80, heads: 1),

        // 720K 3.5" Double Sided Double Density
        Disk.Geometry(sectorsPerTrack: 9, tracksPerHead: 80, heads: 2),

        // 1440K 1.44M  3.5" Double Sided High Density
        Disk.Geometry(sectorsPerTrack: 18, tracksPerHead: 80, heads: 2),

        // 1680K 3.5" Double Sided High Density
        Disk.Geometry(sectorsPerTrack: 21, tracksPerHead: 80, heads: 2),

        // 1720K 3.5" Double Sided High Density
        Disk.Geometry(sectorsPerTrack: 21, tracksPerHead: 82, heads: 2),

        // 2880K 2.88M 3.5" Double Sided Extended Density
        Disk.Geometry(sectorsPerTrack: 36, tracksPerHead: 80, heads: 2),
    ]


    private var disks: [Disk?] = [nil, nil]
    private var mediaChanged = [false, false]
    private var diskTypeForFormat: [UInt8] = [0, 0]
    private var mediaTypeForFormat: [Disk.Geometry?] = [nil, nil]
    private var lastStatus: [Disk.Status] = [.ok, .ok]


    static func parseCommandLineArguments(_ argument: String) -> Disk? {
        return diskForImage(path: argument)
    }


    private static func diskForImage(path: String) -> Disk {
        guard let size = Disk.fileSizeInBytes(for: path) else {
            fatalError("Cant read disk size for \(path)")
        }

        for geometry in floppyGeometries {
            if size == UInt64(geometry.capacity) {
                if let disk = Disk(imageName: path, geometry: geometry, floppyDisk: true) {
                    return disk
                }
            }
        }
        fatalError("Cant find disk geometry for \(path)")
    }


    init(disk1Path: String? = nil, disk2Path: String? = nil) {
        if let disk1Path = disk1Path {
            try! self.insert(diskPath: disk1Path, intoDrive: 0)
        }
        if let disk2Path = disk2Path {
            try! self.insert(diskPath: disk2Path, intoDrive: 1)
        }
    }

    init(disk1: Disk? = nil, disk2: Disk? = nil) {
        if let disk1 = disk1 {
            guard disk1.isFloppyDisk else { fatalError("Not a floppy disk") }
            disks[0] = disk1
        }

        if let disk2 = disk2 {
            guard disk2.isFloppyDisk else { fatalError("Not a floppy disk") }
            disks[1] = disk2
        }
    }


    func eject(drive: Int) throws {
        guard drive < 2 else { throw DiskError.invalidDrive }
        disks[drive] = nil
        mediaChanged[drive] = true
        diskTypeForFormat[drive] = 0
        mediaTypeForFormat[drive] = nil
    }


    func insert(diskPath: String, intoDrive drive: Int) throws {
        guard drive < 2 else { throw DiskError.invalidDrive }
        let disk = Self.diskForImage(path: diskPath)
        disks[drive] = disk
        debugLog("FDC: fd\(drive) \(diskPath): \(disk.geometry)")
    }



    func biosCall(_ ax: UInt16, _ vm: VirtualMachine) {
        let vcpu = vm.vcpus[0]
        let drive = Int(vcpu.registers.dl & 1)
        let function = UInt8(ax >> 8)

        var bda = BDA()

        guard let diskFunction = Disk.BIOSFunction(rawValue: function) else {
            let status = Disk.Status.invalidCommand
            vcpu.registers.ah = status.rawValue
            vcpu.registers.rflags.carry = true
            lastStatus[drive] = status
            bda.floppyDriveStatus = status.rawValue
            fatalError("FDC: function = 0x\(String(function, radix: 16)) drive = \(String(vcpu.registers.dl, radix: 16))H not implemented")
        }

        let status: Disk.Status
        if diskFunction == .getDiskType {
            if disks[drive] == nil {
                vcpu.registers.ah = 0   // No such drive
            } else {
                vcpu.registers.ah = 1   // Floppy without changeline support FIXME
            }
            status = .ok
            vcpu.registers.rflags.carry = false
        } else {
            if let disk = disks[drive] {
                if vcpu.registers.ah == Disk.BIOSFunction.getStatus.rawValue {
                    vcpu.registers.ah = bda.floppyDriveStatus
                    vcpu.registers.rflags.carry = false
                    return
                }
                status = biosCallFor(diskFunction, drive: drive, disk: disk, vm: vm, vcpu: vcpu)
            } else {
                status = .undefinedError
            }
        }

        if status != .ok {
            debugLog("FDC: command \(diskFunction) from drive \(drive) error: \(status)")
        }

        vcpu.registers.ah = status.rawValue
        vcpu.registers.rflags.carry = (status != .ok)
        bda.floppyDriveStatus = status.rawValue
        lastStatus[drive] = status
    }


    private func biosCallFor(_ diskFunction: Disk.BIOSFunction, drive: Int, disk: Disk, vm: VirtualMachine, vcpu: VirtualMachine.VCPU) -> Disk.Status {

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

                if let geometry = mediaTypeForFormat[drive] {
                    let sectorCount = Int(vcpu.registers.al)
                    let track = Int(vcpu.registers.ch)
                    if track >= geometry.tracksPerHead {
                        return .ok
                    }
                    let head = Int(vcpu.registers.dh)
                    debugLog("Format track, media geometry = \(geometry)")
                    debugLog("Format head:  \(head) track: \(track): sectorCount: \(sectorCount)")
                    status = disk.formatTrack(track, head: head, sectorCount: sectorCount)
                } else {
                    debugLog("No geometry set for format of drive \(drive)")
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
                    vcpu.registers.dl = UInt8(disks.filter { $0 != nil }.count) // drive count
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
                if mediaChanged[drive] == false {
                    status = .ok
                } else {
                    status = .changeLineActive
                }
                mediaChanged[drive] = false    // Reset changeline

            case .setDiskTypeForFormat:
                showRegisters(vcpu)
                diskTypeForFormat[drive] = vcpu.registers.al
                let geometry: Disk.Geometry?
                switch vcpu.registers.al {
                    // Note the drive type is ignored, only sectorsPerHead, tracksPerHead is relevant.
                    case 0x01: geometry = Self.floppyGeometries[3]  // 360K disk in 360K drive
                    case 0x02: geometry = Self.floppyGeometries[3]  // 360K disk in 1.2M drive
                    case 0x03: geometry = Self.floppyGeometries[6]  // 1.2M disk in 1.2M dirve
                    case 0x04: geometry = Self.floppyGeometries[8]  // 720 disk in 720K/1.2M dirve
                    default:
                        debugLog("FDC: setDiskTypeForFormat no matching format for \(vcpu.registers.al)")
                        geometry = nil
                }

                if let newGeometry = geometry {
                    debugLog("FDC: Found matching geometry: \(newGeometry)")
                    mediaTypeForFormat[drive] = newGeometry
                    status = .ok
                } else {
                    status = .invalidMedia
                }

            case .setMediaTypeForFormat:
                // TODO: Determine why DOS tries to format track 80 (ie 81st track) which always fails
                // Where is it getting 81 tracks from?
                let (tracks, sectorsPerTrack) = Disk.trackAndSectorFrom(cx: vcpu.registers.cx)
                debugLog("FDC: setMediaTypeForFormat: tracks \(tracks) sectorsPerTrack: \(sectorsPerTrack)")

                mediaTypeForFormat[drive] = nil
                for geometry in Self.floppyGeometries {
                    // Ignore single sided disks
                    if geometry.heads == 2, geometry.tracksPerHead == tracks, geometry.sectorsPerTrack == sectorsPerTrack {
                        mediaTypeForFormat[drive] = geometry
                        break
                    }
                }
                if let newGeometry = mediaTypeForFormat[drive] {
                    debugLog("FDC: Found matching geometry \(newGeometry)")
                    status = .ok
                } else {
                    debugLog("FDC: setMediaTypeForFormat: cant find matching geometry")
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
        }

        if status == .invalidCommand {
            debugLog("FDC: Invalid command: \(diskFunction)")
        } else if status != .ok {
            debugLog("FD: \(diskFunction) returned status \(status)")
            showRegisters(vcpu)
        }
        return status
    }
}
