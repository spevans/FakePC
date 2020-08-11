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

    static func parseCommandLineArguments(_ parameters: String) -> Disk? {
        var tracks: Int?
        var heads: Int?
        var sectors: Int?
        var imageFile: String?
        var readOnly = false

        for part in parameters.split(separator: ",") {
            if part == "ro" {
                readOnly = true
                continue
            }
            let option = String(part).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            guard option.count == 2 else { fatalError("Invalid option: \(parameters)") }
            switch option[0] {
                case "t": if let t = Int(option[1]) { tracks = t }  else { fatalError("Invalid tracks: \(option[1])") }
                case "h": if let h = Int(option[1]) { heads = h  }  else { fatalError("Invalid heads: \(option[1])") }
                case "s": if let s = Int(option[1]) { sectors = s } else { fatalError("Invalid sectors: \(option[1])") }
                case "img": imageFile = String(option[1])
                default: fatalError("Invalid disk option \(option[0])")
            }
        }
        if let tracks = tracks, let sectors = sectors, let heads = heads, let imageFile = imageFile {
            let geometry = Disk.Geometry(sectorsPerTrack: sectors, tracksPerHead: tracks, heads: heads)
            return Disk(imageName: imageFile, geometry: geometry, floppyDisk: false, readOnly: readOnly)
        } else {
            fatalError("Disk specifiction \(parameters) is missing track, sector head or imageFile")
        }
    }

    private let disks: [Disk?]
    private var lastStatus: [Disk.Status] = [.ok, .ok]

    // Hard drives are already attached at power on so need to be passed to init()
    init(disk1: Disk? = nil, disk2: Disk? = nil) {
        disks = [disk1, disk2]
    }


    func biosCall(_ ax: UInt16, _ vm: VirtualMachine) {
        let vcpu = vm.vcpus[0]
        let drive = Int(vcpu.registers.dl - 0x80)
        let function = UInt8(ax >> 8)

        guard let diskFunction = Disk.BIOSFunction(rawValue: function) else {
            let status = Disk.Status.invalidCommand
            vcpu.registers.ah = status.rawValue
            vcpu.registers.rflags.carry = true
            lastStatus[drive] = status
            fatalError("HDC: function = 0x\(String(function, radix: 16)) drive = \(String(vcpu.registers.dl, radix: 16))H not implemented")
        }


        let status: Disk.Status
        if diskFunction == .getDiskType {
            if let disk = disks[drive] {
                vcpu.registers.ah = 3   // Hard Drive
                let sectors = disk.geometry.totalSectors
                vcpu.registers.cx = UInt16(sectors >> 16)
                vcpu.registers.dx = UInt16(truncatingIfNeeded: sectors)
            } else {
                vcpu.registers.ah = 0   // No such drive
            }
            status = .ok
            vcpu.registers.rflags.carry = false
            return
        } else {
            if let disk = disks[drive] {
                if vcpu.registers.ah == Disk.BIOSFunction.getStatus.rawValue {
                    vcpu.registers.ah = lastStatus[drive].rawValue
                    vcpu.registers.rflags.carry = false
                    return
                }
                status = biosCallFor(diskFunction, drive: drive, disk: disk, vm: vm, vcpu: vcpu)
            } else {
                status = .undefinedError
            }
        }

        if status != .ok {
            debugLog("HDC: command \(diskFunction) from drive \(drive) error: \(status)")
        }

        vcpu.registers.ah = status.rawValue
        vcpu.registers.rflags.carry = (status != .ok)
        lastStatus[drive] = status
    }


    private func biosCallFor(_ diskFunction: Disk.BIOSFunction, drive: Int, disk: Disk, vm: VirtualMachine, vcpu: VirtualMachine.VCPU) -> Disk.Status {

        let status: Disk.Status
        switch diskFunction {

            case .resetDisk:
                status = disk.setCurrentTrack(0)

            case .getStatus:
                status = lastStatus[drive]
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
                status = .invalidCommand    // Only for floppy drives

            case .formatTrackSetBadSectors:
                status = .invalidCommand

            case .formatDrive:
                status = .invalidCommand

            case .readDriveParameters:
                status = disk.getDriveParameters(vcpu: vcpu)
                if status == .ok {
                    vcpu.registers.bl = 00  // drive type
                    vcpu.registers.dl = UInt8(disks.filter { $0 != nil }.count) // drive count
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
                let status1 = disks[0]?.setCurrentTrack(0) ?? .ok
                let status2 = disks[1]?.setCurrentTrack(0) ?? .ok
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
                status = disk.extendedRead(vcpu: vcpu)

            case .extendedWriteSectors:
                status = disk.extendedWrite(vcpu: vcpu)

            case .extendedVerifySectors:
                status = disk.extendedVerify(vcpu: vcpu)

            case .extendedSeek:
                status = .invalidCommand

            case .extendedGetDriveParameters:
                status = disk.extendedGetDriveParameters(vcpu: vcpu)
        }

        if status == .invalidCommand {
            debugLog("HDC: Invalid command: \(diskFunction)")
        } else if status != .ok {
            debugLog("HDC: \(diskFunction) returned status \(status)")
            showRegisters(vcpu)
        }
        return status
    }
}
