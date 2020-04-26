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
            debugLog("HDC: command \(function) from drive \(drive) error: \(status)")
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
                showRegisters(vcpu)
                vcpu.registers.bl = 04
                let cylinders = disk.geometry.tracksPerHead
                vcpu.registers.ch = UInt8(cylinders & 0xff)
                vcpu.registers.cl = UInt8(disk.geometry.sectorsPerTrack & 0x3f) | (UInt8(cylinders >> 6) & 0xc0)
                vcpu.registers.dh = UInt8(disk.geometry.heads - 1)
                vcpu.registers.dl = UInt8(disks.filter { $0 != nil }.count)
                status = .ok

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
        }

        return status
    }
}
