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
public final class Disk {

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
        guard sectorCount <= 72 else {
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
