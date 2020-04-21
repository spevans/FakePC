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
    private var mediaChangeStatus = [false, false]
    private var diskTypeForFormat: [UInt8] = [0, 0]
    private var lastStatus: [Disk.Status] = [.ok, .ok]

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
            print("FDC: command \(function) from drive \(drive) error: \(status)")
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
                        status = disk.readSectors(into: buffer, fromSector: operation.startSector, count: operation.sectorCount)
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
                            status = disk.writeSectors(from: buffer, toSector: operation.startSector, count: operation.sectorCount)
                    }
                }

            case .verifySectors:
                switch disk.validateSectorOperation(vcpu: vcpu) {
                    case .failure(let error):
                        status = error

                    case .success(let operation):
                        let ptr = vm.memoryRegions[0].rawBuffer.baseAddress!.advanced(by: operation.bufferOffset)
                        let buffer = UnsafeRawBufferPointer(start: ptr, count: operation.bufferSize)
                        status = disk.verifySectors(in: buffer, toSector: operation.startSector, count: operation.sectorCount)
                }

            case .formatTrack:
                fatalError("FDC: Implement formatTrack")

            case .formatTrackSetBadSectors:
                status = .invalidCommand

            case .formatDrive:
                status = .invalidCommand

            case .readDriveParameters:
                showRegisters(vcpu)
                vcpu.registers.bl = 04
                let cylinders = disk.tracksPerHead
                vcpu.registers.ch = UInt8(cylinders & 0xff)
                vcpu.registers.cl = UInt8(disk.sectorsPerTrack & 0x3f) | (UInt8(cylinders >> 6) & 0xc0)
                vcpu.registers.dh = UInt8(disk.heads - 1)
                vcpu.registers.dl = 1
                status = .ok

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
                fatalError("FDC: readDASDType should have been handled earlier")

            case .changeOfDiskStatus:
                // Change line inactive, disk not changed
                if mediaChangeStatus[drive] == false {
                    status = .ok
                } else {
                    status = .changeLineActive
                }
                mediaChangeStatus[drive] = false    // Reset changeline

            case .setDiskTypeForFormat:
                diskTypeForFormat[drive] = vcpu.registers.al
                status = .ok

            case .setMediaTypeForFormat:
                // TODO
                fatalError("FDC: Implement setMediaTypeForFormat")

            case .parkFixedDiskHeads:
                status = .invalidCommand

            case .formatESDIDriveUnit:
                status = .invalidCommand
        }

        return status
    }
}
