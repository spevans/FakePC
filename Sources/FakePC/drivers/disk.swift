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

        // LBA 0 is Head 0, Track 0, sector 0
        func logicalSector(head: Int, track: Int, sector: Int) -> UInt64 {
            return UInt64((head * sectorsPerTrack) + (track * sectorsPerTrack * heads) + sector)
        }
    }

    let imageURL: URL
    let fileHandle: FileHandle
    let geometry: Geometry
    var sectorSize: Int { geometry.sectorSize }
    var data: Data
    let isReadOnly: Bool

    private(set) var lastStatus: Status = .ok
    private var currentTrack = 0


    static func fileSizeInBytes(for path: String) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        return attributes[.size] as? UInt64
    }


    init?(imageName: String, geometry: Geometry? = nil, readOnly: Bool = false) {
        imageURL = URL(fileURLWithPath: imageName, isDirectory: false)
        isReadOnly = readOnly || !FileManager.default.isWritableFile(atPath: imageName)
        do {
            if isReadOnly {
                try fileHandle = FileHandle(forReadingFrom: imageURL)
            } else {
                try fileHandle = FileHandle(forUpdating: imageURL)
            }

            guard let data = try fileHandle.readToEnd() else {
                throw DiskError.zeroSizedMedia
            }
            self.data = data
        } catch {
            fatalError("Error initialising Disk from: '\(imageName)': \(error)")
        }

        if let geometry = geometry {
            self.geometry = geometry
            guard geometry.capacity == UInt64(data.count) else {
                debugLog("Image size != data size")
                return nil
            }
        } else {
            let sectorSize = 512
            let sectors = (data.count + sectorSize - 1) / sectorSize
            self.geometry = Geometry(sectors: sectors, sectorSize: sectorSize)
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

        var offset: Int { Int(startSector) * disk.sectorSize }
        var size: Int { Int(sectorCount) * disk.sectorSize }
        var range: Range<Int> { offset..<(offset + size) }

        func readSectors(into buffer: UnsafeMutableRawBufferPointer) -> Status {
            assert(size == buffer.count)
            disk.data.copyBytes(to: buffer, from: range)
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
            disk.data.replaceSubrange(range, with: buffer)
            debugLog("DISK: Writing \(size) bytes @ offset \(offset)")
            disk.fileHandle.seek(toFileOffset: UInt64(offset))
            let subData = disk.data[range]
            disk.fileHandle.write(subData)
            debugLog("DISK: Wrote \(subData.count) bytes")
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
        debugLog("DISK: startSector: \(startSector) sectorSize: \(sectorSize) offset: \(offset)")
        debugLog("DISK: Formatting track \(track) head: \(head) Writing \(size) bytes @ offset \(offset)")
        fileHandle.seek(toFileOffset: UInt64(offset))
        fileHandle.write(zeros)
        debugLog("DISK: Wrote \(zeros.count) bytes")
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
}
