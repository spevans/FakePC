//
//  Int13Disk.swift
//  FakePC
//
//  Created by Simon Evans on 31/03/2021.
//  Copyright © 2021 Simon Evans. All rights reserved.
//
//  INT 13H BIOS Disk services.
//

import HypervisorKit

// Maps BIOS disk number to Disk, 00-7f, floppies 0x80-0xDF hard disk, 0xE0-0xEF CDROM

private enum PhysicalMedia {
    case fdc(Int)  // channel 0 or 1
    case hdc(Int, Int)  // controller 0/1, channel 0/1
    case cdromEmulatingFloppy(Disk)
    case cdromEmulatingHarddisk(Disk)
}

private var disks: [UInt8: PhysicalMedia] = [:]

internal func setupDisks(_ isa: ISA) {
    disks[0] = PhysicalMedia.fdc(0)
    disks[1] = PhysicalMedia.fdc(1)

    var hd = UInt8(0x80)
    var cdrom = UInt8(0xE0)

    for (hdcIdx, hdc) in isa.hardDriveControllers.enumerated() {
        for (channel, disk) in hdc.disks.enumerated() {
            guard let disk = disk else { continue }
            if disk.isHardDisk {
                disks[hd] = PhysicalMedia.hdc(hdcIdx, channel)
                hd += 1
            } else if disk.isCdrom {
                disks[cdrom] = PhysicalMedia.hdc(hdcIdx, channel)
                cdrom += 1
            } else {
                fatalError("Disk in HDC \(hdcIdx),\(channel) is not a harddisk or cdrom")
            }
        }
    }
    logger.debug("BIOS disk mapping:")
    for key in disks.keys.sorted() {
        logger.debug("\(String(key, radix: 16)): \(disks[key]!)")
    }
}


internal func diskCall(function: UInt8, vm: VirtualMachine, isa: ISA) {
    let registers = vm.vcpus[0].registers
    let drive = registers.dl

    guard let diskFunction = Disk.BIOSFunction(rawValue: function) else {
        let status = Disk.Status.invalidCommand
        registers.ah = status.rawValue
        registers.rflags.carry = true
        if drive < 0x80 {
            var bda = BDA()
            bda.floppyDriveStatus = status.rawValue
        }
        logger.debug("DISK: function: 0x\(String(function, radix: 16)) drive = \(String(drive, radix: 16))H not implemented")
        return
    }


    var bda = BDA()
    var status: Disk.Status = .undefinedError

    if let media = disks[drive] {
        switch media {
            case .fdc(let channel):
                let fdc = isa.floppyDriveController
                let disk = fdc.disks[channel]
                if diskFunction == .getDiskType {
                    if disk != nil {
                        registers.ah = 1  // Floppy without changeline support FIXME
                    } else {
                        registers.ah = 0  // No such drive
                    }
                    status = .ok
                    registers.rflags.carry = false
                    return
                } else {
                    if disk != nil {
                        status = biosCallForFloppy(diskFunction, fdc: fdc, drive: channel, vm: vm)
                    } else {
                        status = .undefinedError
                    }
                }
                bda.floppyDriveStatus = status.rawValue

            case .hdc(let controller, let channel):
                let hdc = isa.hardDriveControllers[controller]
                let disk = hdc.disks[channel]
                if diskFunction == .getDiskType {
                    if let disk = disk, disk.isHardDisk {
                        registers.ah = 3  // Hard Drive
                        let sectors = disk.geometry.totalSectors
                        registers.cx = UInt16(sectors >> 16)
                        registers.dx = UInt16(truncatingIfNeeded: sectors)
                    } else {
                        registers.ah = 0  // No such drive - includes cdroms
                    }
                    status = .ok
                    registers.rflags.carry = false
                    return
                } else {
                    if let disk = disk {
                        if disk.isHardDisk {
                            status = biosCallForHardDrive(diskFunction, hdc: hdc, drive: channel, vm: vm)
                        } else {
                            status = biosCallForCdrom(diskFunction, disk: disk, vm: vm)
                        }
                    } else {
                        status = .undefinedError
                    }
                }
                bda.statusLastHardDiskOperation = status.rawValue

            case .cdromEmulatingFloppy(let cdrom):
                status = biosCallForCdrom(diskFunction, disk: cdrom, vm: vm)
                bda.floppyDriveStatus = status.rawValue

            case .cdromEmulatingHarddisk(let cdrom):
                status = biosCallForCdrom(diskFunction, disk: cdrom, vm: vm)
                bda.statusLastHardDiskOperation = status.rawValue
        }
    }


    if status != .ok {
        logger.debug("DISK: command \(diskFunction) from drive \(drive) error: \(status)")
    }

    registers.ah = status.rawValue
    registers.rflags.carry = (status != .ok)
}


// INT 13h BIOS Interface
extension Disk {

    enum BIOSFunction: UInt8 {
        case resetDisk = 0
        case getStatus = 1
        case readSectors = 2
        case writeSectors = 3
        case verifySectors = 4
        case formatTrack = 5
        case formatTrackSetBadSectors = 6
        case formatDrive = 7
        case readDriveParameters = 8
        case initialiseHDControllerTables = 9
        case readLongSector = 0xA
        case writeLongSector = 0xB
        case seekToCylinder = 0xC
        case alternateDiskReset = 0xD
        case readSectorBuffer = 0xE
        case writeSectorBuffer = 0xF
        case testForDriveReady = 0x10
        case recalibrateDrive = 0x11
        case controllerRamDiagnostic = 0x12
        case driveDiagnostic = 0x13
        case controllerInternalDiagnostic = 0x14
        case getDiskType = 0x15
        case changeOfDiskStatus = 0x16
        case setDiskTypeForFormat = 0x17
        case setMediaTypeForFormat = 0x18
        case parkFixedDiskHeads = 0x19
        case formatESDIDriveUnit = 0x1A
        case checkExtensionsPresent = 0x41
        case extendedReadSectors = 0x42
        case extendedWriteSectors = 0x43
        case extendedVerifySectors = 0x44
        case lockUnlockDrive = 0x45
        case ejectMedia = 0x46
        case extendedSeek = 0x47
        case extendedGetDriveParameters = 0x48
        case extendedMediaChange = 0x49
        case initiateDiskEmulationForCdrom = 0x4A
        case terminateDiskEmulationForCdrom = 0x4B
        case initiateDiskEmulateForCdromAndBoot = 0x4C
        case returnBootCatalogForCdrom = 0x4D
        case sendPacketCommand = 0x4E
    }

    enum Status: UInt8, Error {
        case ok = 0
        case invalidCommand = 1
        case badSector = 2
        case writeProtected = 3
        case sectorNotFound = 4
        case resetFailed = 5
        case changeLineActive = 6
        case parameterActivityFailed = 7
        case dmaOverrun = 8
        case dmaOver64KBoundary = 9
        case badSectorDetected = 0xa
        case badTrackDetected = 0xb
        case invalidMedia = 0xc
        case invalidNumberOfSectors = 0xd
        case addressMarkDetected = 0xe
        case dmaOutOfRange = 0xf
        case dataError = 0x10
        case correctedDataError = 0x11
        case controllerFailure = 0x20
        case noMediaInDrive = 0x31
        case seekFailure = 0x40
        case driveTimedOut = 0x80
        case driveNotReady = 0xAA
        case undefinedError = 0xBB
        case writeFault = 0xCC
        case statusError = 0xE0
        case senseOperationFailed = 0xFF
    }


    func checkExtensionsPresent(vcpu: VirtualMachine.VCPU) -> Status {
        guard vcpu.registers.bx == 0x55aa else { return .invalidCommand }
        vcpu.registers.bx = 0xaa55
        vcpu.registers.ax = 0x2000  // Extensions 2.0, EDD-1.0
        vcpu.registers.cx = 0x1  // extended disk access functions (AH=42h-44h,47h,48h) supported
        if isCdrom {
            vcpu.registers.cx = 0x3  // removable drive controller functions (AH=45h,46h,48h,49h,INT 15/AH=52h) supported
        }
        return .ok
    }


    private func diskAccessPacket(_ packet: UnsafeRawPointer) -> SectorOperation? {
        // Check packet size
        guard packet.load(fromByteOffset: 0, as: UInt8.self) == 16 else { return nil }

        // Check Reserved byte
        guard packet.load(fromByteOffset: 1, as: UInt8.self) == 0 else { return nil }

        let sectorCount = Int(packet.unalignedLoad(fromByteOffset: 2, as: UInt16.self))
        guard sectorCount <= 128 else { return nil }
        let size = sectorCount * geometry.sectorSize
        guard size <= 0x10000 else { return nil }

        let bufferOffset: UInt16 = packet.unalignedLoad(fromByteOffset: 4, as: UInt16.self)
        let bufferSegment: UInt16 = packet.unalignedLoad(fromByteOffset: 6, as: UInt16.self)
        guard bufferSegment != 0xffff || bufferOffset != 0xffff else { return nil }
        guard UInt32(0x10000) - UInt32(bufferOffset) >= UInt32(size) else {
            return nil  // .failure(.dmaOver64KBoundary)
        }

        let bufferAddress = Int(bufferSegment) << 4 + Int(bufferOffset)
        guard bufferAddress < 0xF0000 else { return nil }

        let lba: UInt64 = packet.unalignedLoad(fromByteOffset: 8, as: UInt64.self)
        guard Int(lba) + sectorCount <= geometry.totalSectors else { return nil }

        return SectorOperation(
            disk: self, startSector: lba,
            sectorCount: sectorCount,
            bufferOffset: bufferAddress,
            bufferSize: sectorCount * geometry.sectorSize)
    }


    func extendedRead(vcpu: VirtualMachine.VCPU) -> Status {
        let vm = fakePC.vm
        let offset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
        guard let dap = try? vm.memory(at: PhysicalAddress(offset), count: 16) else { return .invalidCommand }

        guard let sectorOperation = diskAccessPacket(UnsafeRawPointer(dap)) else { return .invalidCommand }
        guard
            let ptr = try? vm.memory(
                at: PhysicalAddress(UInt(sectorOperation.bufferOffset)),
                count: UInt64(sectorOperation.bufferSize))
        else { return .dmaOver64KBoundary }
        let buffer = UnsafeMutableRawBufferPointer(start: ptr, count: sectorOperation.bufferSize)
        return sectorOperation.readSectors(into: buffer)
    }


    func extendedWrite(vcpu: VirtualMachine.VCPU) -> Status {
        let vm = fakePC.vm
        let offset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
        guard let dap = try? vm.memory(at: PhysicalAddress(offset), count: 16) else { return .invalidCommand }
        guard let sectorOperation = diskAccessPacket(UnsafeRawPointer(dap)) else { return .invalidCommand }
        guard !sectorOperation.disk.isReadOnly else { return .writeProtected }

        guard
            let ptr = try? vm.memory(
                at: PhysicalAddress(UInt(sectorOperation.bufferOffset)),
                count: UInt64(sectorOperation.bufferSize))
        else { return .dmaOver64KBoundary }
        let buffer = UnsafeRawBufferPointer(start: ptr, count: sectorOperation.bufferSize)
        if sectorOperation.startSector == 0 {
            logger.debug("\(vm.memoryRegions[0].dumpMemory(at: Int(sectorOperation.bufferOffset), count: 512))")
        }
        let status = sectorOperation.writeSectors(from: buffer)
        if status != .ok {
            // Update the DAP with the number of sectors written - This is untouched from the request
            // so only set to zero if the write failed
            let zero = UInt16(0)
            dap.unalignedStoreBytes(of: zero, toByteOffset: 2, as: UInt16.self)
        }
        return status
    }


    func extendedVerify(vcpu: VirtualMachine.VCPU) -> Status {
        let vm = fakePC.vm
        let offset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
        guard let dap = try? vm.memory(at: PhysicalAddress(offset), count: 16) else { return .invalidCommand }
        guard let sectorOperation = diskAccessPacket(UnsafeRawPointer(dap)) else { return .invalidCommand }
        guard
            let ptr = try? vm.memory(
                at: PhysicalAddress(UInt(sectorOperation.bufferOffset)),
                count: UInt64(sectorOperation.bufferSize))
        else { return .dmaOver64KBoundary }
        let buffer = UnsafeRawBufferPointer(start: ptr, count: sectorOperation.bufferSize)
        let status = sectorOperation.verifySectors(using: buffer)
        if status != .ok {
            // Update the DAP with the number of sectors written - This is untouched from the request
            // so only set to zero if the write failed
            let zero = UInt16(0)
            dap.unalignedStoreBytes(of: zero, toByteOffset: 2, as: UInt16.self)
        }
        return status
    }


    func extendedSeek(vcpu: VirtualMachine.VCPU) -> Status {
        return .invalidCommand
    }


    func getDriveParameters(vcpu: VirtualMachine.VCPU) -> Status {
        vcpu.registers.bl = 04
        if geometry.hasCHS {
            let maxCylinderNumber = geometry.tracksPerHead - 1
            vcpu.registers.ch = UInt8(maxCylinderNumber & 0xff)
            vcpu.registers.cl = UInt8(geometry.sectorsPerTrack & 0x3f) | (UInt8(maxCylinderNumber >> 2) & 0xc0)
            vcpu.registers.dh = UInt8(geometry.heads - 1)
        } else {
            vcpu.registers.ch = 0
            vcpu.registers.cl = 0
            vcpu.registers.dh = 0
        }
        return .ok
    }


    func extendedGetDriveParameters(vcpu: VirtualMachine.VCPU) -> Status {
        let vm = fakePC.vm
        let offset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
        let parameterBuffer: UnsafeMutableRawPointer
        do {
            parameterBuffer = try vm.memory(at: PhysicalAddress(offset), count: 16)
        } catch {
            return .invalidCommand
        }

        // Check packet size
        let packetSize = parameterBuffer.load(fromByteOffset: 0, as: UInt16.self)
        guard packetSize == 0x1A || packetSize == 0x1E else { return .invalidCommand }

        //        let bufferSize = UInt16(0x1E)     // Size for version 2.x
        //        parameterBuffer.unalignedStoreBytes(of: bufferSize, toByteOffset: 0, as: UInt16.self)

        var informationFlags = UInt16(0)  // DMA boundary errors not handled
        if geometry.hasCHS { informationFlags |= 2 }  // has CHS
        if isFloppyDisk || isCdrom { informationFlags |= 4 }  // removable drive
        if isCdrom {
            informationFlags |= 16  // drive has change line support
            informationFlags |= 32  // drive can be locked
        }

        parameterBuffer.unalignedStoreBytes(of: informationFlags, toByteOffset: 2, as: UInt16.self)
        let tracks = UInt32(geometry.tracksPerHead)
        let heads = UInt32(geometry.heads)
        let sectors = UInt32(geometry.sectorsPerTrack)
        let totalSectorsOnDrive = UInt64(geometry.totalSectors)

        parameterBuffer.unalignedStoreBytes(of: tracks, toByteOffset: 4, as: UInt32.self)
        parameterBuffer.unalignedStoreBytes(of: heads, toByteOffset: 8, as: UInt32.self)
        parameterBuffer.unalignedStoreBytes(of: sectors, toByteOffset: 0xC, as: UInt32.self)
        parameterBuffer.unalignedStoreBytes(of: totalSectorsOnDrive, toByteOffset: 0x10, as: UInt64.self)
        parameterBuffer.unalignedStoreBytes(of: UInt16(geometry.sectorSize), toByteOffset: 0x18, as: UInt16.self)

        if packetSize == 0x1E {
            let eddConfigurationParameters = UInt32(0xffff_ffff)  // Parameters not available
            parameterBuffer.unalignedStoreBytes(of: eddConfigurationParameters, toByteOffset: 0x1A, as: UInt32.self)
        }

        return .ok
    }
}
