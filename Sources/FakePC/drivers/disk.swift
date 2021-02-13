//
//  disk.swift
//  FakePC
//
//  Created by Simon Evans on 01/01/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Floppy and Hard disk functionality for BIOS INT 13h calls.
//

import Foundation
import HypervisorKit


enum DiskError: Error {
    case invalidMedia
    case invalidDrive
    case zeroSizedMedia
}


#if os(macOS)
extension FileHandle {
    // This is missing in Darwin Foundation
    // TODO: Add an objc version that catches the underlying exception and throws it
    func readToEnd() throws -> Data? {
        return readDataToEndOfFile()
    }
}
#endif

// Represents either 1 floppy or hard disk including BIOS call functions
// Storage is implemented as a URL to a file on the host drive.
final class Disk {

    enum DriveType {
        case floppy
        case harddisk
        case cdrom
    }


    struct Geometry: Equatable, Hashable {
        let sectorsPerTrack: Int
        let tracksPerHead: Int
        let heads: Int
        let sectorSize: Int
        let totalSectors: Int

        var hasCHS: Bool { heads != 0 && tracksPerHead != 0 && sectorsPerTrack != 0 }
        var capacity: UInt64 { UInt64(sectorSize) * UInt64(totalSectors) }

        // LBA only, no CHS specified
        init(sectors: Int, sectorSize: Int = 512) {
            totalSectors = sectors
            self.sectorSize = sectorSize
            sectorsPerTrack = 0
            tracksPerHead = 0
            heads = 0
        }

        // CHS
        init(sectorsPerTrack: Int, tracksPerHead: Int, heads: Int, sectorSize: Int = 512) {
            self.sectorsPerTrack = sectorsPerTrack
            self.tracksPerHead = tracksPerHead
            self.heads = heads
            self.sectorSize = sectorSize
            totalSectors = sectorsPerTrack * tracksPerHead * heads
        }

        // LBA
        init(totalSize: Int, sectorSize: Int) {
            sectorsPerTrack = 0
            tracksPerHead = 0
            heads = 0
            self.sectorSize = sectorSize
            self.totalSectors = totalSize / sectorSize  // Round down
        }

        // LBA 0 is Head 0, Track 0, sector 0
        func logicalSector(head: Int, track: Int, sector: Int) -> UInt64 {
            return UInt64((head * sectorsPerTrack) + (track * sectorsPerTrack * heads) + sector)
        }
    }

    let imageURL: URL
    let fileHandle: FileHandle
    let geometry: Geometry
    let isReadOnly: Bool
    let device: DriveType
    let totalSize: UInt64

    private(set) var lastStatus: Status = .ok
    private var currentTrack = 0

    var sectorSize: Int { geometry.sectorSize }
    var isFloppyDisk: Bool { device == .floppy }
    var isHardDisk: Bool { device == .harddisk }
    var isCdrom: Bool { device == .cdrom }


    static func fileSizeInBytes(path: String) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        return attributes[.size] as? UInt64
    }


    init?(imageName: String, geometry: Geometry? = nil, device: DriveType, readOnly: Bool = false) {
        imageURL = URL(fileURLWithPath: imageName, isDirectory: false)
        isReadOnly = readOnly || !FileManager.default.isWritableFile(atPath: imageName)
        self.device = device

        do {
            if isReadOnly {
                try fileHandle = FileHandle(forReadingFrom: imageURL)
            } else {
                try fileHandle = FileHandle(forUpdating: imageURL)
            }

            totalSize = fileHandle.seekToEndOfFile()
            guard totalSize > 0 else {
                throw DiskError.zeroSizedMedia
            }
        } catch {
            fatalError("Error initialising Disk from: '\(imageName)': \(error)")
        }

        if let geometry = geometry {
            self.geometry = geometry
            guard geometry.capacity == totalSize else {
                logger.debug("Image size != data size")
                return nil
            }
        } else {
            let sectorSize = 512
            let sectors = (totalSize + UInt64(sectorSize) - 1) / UInt64(sectorSize)
            self.geometry = Geometry(sectors: Int(sectors), sectorSize: sectorSize)
        }
    }


    static func trackAndSectorFrom(cx: UInt16) -> (Int, Int) {
        let sector = Int(cx) & 0x3f
        let track = Int(cx) >> 8 | (Int(cx & 0xc0) << 10)
        return (track, sector)
    }


    func logicalSector(cx: UInt16, dh: UInt8) -> UInt64? {
        let head = Int(dh)    // DH = head
        let sector = Int(cx) & 0x3f
        let track = Int(cx) >> 8 | (Int(cx & 0xc0) << 10)
        guard sector > 0 && sector <= geometry.sectorsPerTrack && track < geometry.tracksPerHead && head < geometry.heads else {
            return nil
        }
        return geometry.logicalSector(head: head, track: track, sector: sector - 1)
    }


    // Used by BIOS calls for reading/writing/verifying sectors
    // Converts al, cx, dx, es:bx into a SectorOperation and validates input
    struct SectorOperation {
        let disk: Disk
        let startSector: UInt64
        let sectorCount: Int
        let bufferOffset: Int
        let bufferSize: Int

        var offset: UInt64 { startSector * UInt64(disk.sectorSize) }
        var size: Int { Int(sectorCount) * disk.sectorSize }


        func readSectors(into buffer: UnsafeMutableRawBufferPointer) -> Status {
            disk.fileHandle.seek(toFileOffset: offset)
            let source = disk.fileHandle.readData(ofLength: size)
            assert(size == buffer.count)
            source.copyBytes(to: buffer)
            return .ok
        }


        // Note this doesnt read anything into the buffer or compare the buffer with the data on disk as it is
        // only really supposed to check the sector CRCs (which dont actually exist)
        func verifySectors(using buffer: UnsafeRawBufferPointer) -> Status {
            assert(size == buffer.count)
            return .ok // Dont actually compare the data, only the sector parameters are validated
        }


        func writeSectors(from buffer: UnsafeRawBufferPointer) -> Status {
            guard !disk.isReadOnly else { return .writeProtected }
            assert(size == buffer.count)

            logger.debug("DISK: Writing \(size) bytes @ offset \(offset)")
            let source = Data(buffer)
            disk.fileHandle.seek(toFileOffset: offset)
            disk.fileHandle.write(source)
            logger.debug("DISK: Wrote \(buffer.count) bytes")
            return .ok
        }
    }


    func validateSectorOperation(vcpu: VirtualMachine.VCPU) -> Result<SectorOperation, Disk.Status> {
        guard let startSector = self.logicalSector(cx: vcpu.registers.cx, dh: vcpu.registers.dh) else {
            return .failure(.sectorNotFound)
        }
        let sectorCount = Int(vcpu.registers.al)
        guard sectorCount > 0 && sectorCount <= 63 else {
            return .failure(.invalidNumberOfSectors)
        }

        let size = sectorCount * self.sectorSize
        // Check there is enough space from the buffer to end for segment  (boundary overflow)
        let bx = Int(vcpu.registers.bx)
        guard 0x10000 - bx >= size else {
            return .failure(.dmaOver64KBoundary)
        }
        guard Int(startSector) + sectorCount <= self.geometry.totalSectors else {
            return .failure(.invalidNumberOfSectors)
        }
        let offset = Int(vcpu.registers.es.base) + bx
        let operation = SectorOperation(disk: self, startSector: startSector, sectorCount: sectorCount, bufferOffset: offset, bufferSize: Int(size))
        return .success(operation)
    }


    func formatTrack(_ track: Int, head: Int, sectorCount: Int) -> Status {
        guard !isReadOnly else { return .writeProtected }
        guard geometry.hasCHS else { return .invalidMedia }

        guard track < geometry.tracksPerHead, head < geometry.heads, sectorCount == geometry.sectorsPerTrack else { return .invalidMedia }
        let startSector = geometry.logicalSector(head: head, track: track, sector: 0)

        let offset = startSector * UInt64(sectorSize)
        let size = sectorCount * geometry.sectorSize
        let zeros = Data(count: size)
        logger.debug("DISK: startSector: \(startSector) sectorSize: \(sectorSize) offset: \(offset)")
        logger.debug("DISK: Formatting track \(track) head: \(head) Writing \(size) bytes @ offset \(offset)")
        fileHandle.seek(toFileOffset: UInt64(offset))
        fileHandle.write(zeros)
        logger.debug("DISK: Wrote \(zeros.count) bytes")
        return .ok
    }

    func setCurrentTrack(_ track: Int) -> Status {
        if track < geometry.tracksPerHead {
            currentTrack = track
            return .ok
        } else {
            return .invalidMedia
        }
    }
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
        vcpu.registers.cx = 0x1     // extended disk access functions (AH=42h-44h,47h,48h) supported
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

        let bufferOffset: UInt16 =  packet.unalignedLoad(fromByteOffset: 4, as: UInt16.self)
        let bufferSegment: UInt16 = packet.unalignedLoad(fromByteOffset: 6, as: UInt16.self)
        guard bufferSegment != 0xffff || bufferOffset != 0xffff else { return nil }
        guard UInt32(0x10000) - UInt32(bufferOffset) >= UInt32(size) else {
            return nil // .failure(.dmaOver64KBoundary)
        }

        let bufferAddress = Int(bufferSegment) << 4 + Int(bufferOffset)
        guard bufferAddress < 0xF0000 else { return nil}

        let lba: UInt64 = packet.unalignedLoad(fromByteOffset: 8, as: UInt64.self)
        guard Int(lba) + sectorCount <= geometry.totalSectors else { return nil }

        return SectorOperation(disk: self, startSector: lba,
                               sectorCount: sectorCount,
                               bufferOffset: bufferAddress,
                               bufferSize: sectorCount * geometry.sectorSize)
    }


    func extendedRead(vcpu: VirtualMachine.VCPU) -> Status {
        let offset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
        guard let dap = try? vcpu.vm.memory(at: PhysicalAddress(offset), count: 16) else { return .invalidCommand }

        guard let sectorOperation = diskAccessPacket(UnsafeRawPointer(dap)) else { return .invalidCommand }
        guard let ptr = try? vcpu.vm.memory(at: PhysicalAddress(UInt(sectorOperation.bufferOffset)),
            count: UInt64(sectorOperation.bufferSize)) else { return .dmaOver64KBoundary }
        let buffer = UnsafeMutableRawBufferPointer(start: ptr, count: sectorOperation.bufferSize)
        return sectorOperation.readSectors(into: buffer)
    }


    func extendedWrite(vcpu: VirtualMachine.VCPU) -> Status {
        let offset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
        guard let dap = try? vcpu.vm.memory(at: PhysicalAddress(offset), count: 16) else { return .invalidCommand }
        guard let sectorOperation = diskAccessPacket(UnsafeRawPointer(dap)) else { return .invalidCommand }
        guard !sectorOperation.disk.isReadOnly else { return .writeProtected }

        guard let ptr = try? vcpu.vm.memory(at: PhysicalAddress(UInt(sectorOperation.bufferOffset)),
            count: UInt64(sectorOperation.bufferSize)) else { return .dmaOver64KBoundary }
        let buffer = UnsafeRawBufferPointer(start: ptr, count: sectorOperation.bufferSize)
        if sectorOperation.startSector == 0 {
            debugLog(vcpu.vm.memoryRegions[0].dumpMemory(at: Int(sectorOperation.bufferOffset), count: 512))
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
        let offset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
        guard let dap = try? vcpu.vm.memory(at: PhysicalAddress(offset), count: 16) else { return .invalidCommand }
        guard let sectorOperation = diskAccessPacket(UnsafeRawPointer(dap)) else { return .invalidCommand }
        guard let ptr = try? vcpu.vm.memory(at: PhysicalAddress(UInt(sectorOperation.bufferOffset)),
            count: UInt64(sectorOperation.bufferSize)) else { return .dmaOver64KBoundary }
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
        let offset = UInt(vcpu.registers.ds.base) + UInt(vcpu.registers.si)
        let parameterBuffer: UnsafeMutableRawPointer
        do {
            parameterBuffer = try vcpu.vm.memory(at: PhysicalAddress(offset), count: 16)
        } catch {
            return .invalidCommand
        }

        // Check packet size
        let packetSize = parameterBuffer.load(fromByteOffset: 0, as: UInt16.self)
        guard packetSize == 0x1A || packetSize == 0x1E else { return .invalidCommand }

//        let bufferSize = UInt16(0x1E)     // Size for version 2.x
//        parameterBuffer.unalignedStoreBytes(of: bufferSize, toByteOffset: 0, as: UInt16.self)

        var informationFlags = UInt16(0)    // DMA boundary errors not handled
        if geometry.hasCHS { informationFlags |= 2 } // has CHS
        if isFloppyDisk || isCdrom { informationFlags |= 4 } // removable drive
        if isCdrom {
            informationFlags |= 16 // drive has change line support
            informationFlags |= 32 // drive can be locked
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
            let eddConfigurationParameters = UInt32(0xffff_ffff)   // Parameters not available
            parameterBuffer.unalignedStoreBytes(of: eddConfigurationParameters, toByteOffset: 0x1A, as: UInt32.self)
        }

        return .ok
    }
}
