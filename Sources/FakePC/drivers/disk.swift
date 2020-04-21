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
}

// Represents either 1 floppy or hard disk including BIOS call functions
// Storage is implemented as a URL to a file on the host drive.
final class Disk {

    let imageURL: URL
    var data: Data
    let sectorSize = 512
    let sectorsPerTrack: Int
    let tracksPerHead: Int
    let heads: Int
    let isReadOnly: Bool
    let isHardDisk = false
    private(set) var lastStatus: Status = .ok
    private var currentTrack = 0

    var isFloppyDisk: Bool { !isHardDisk }


    init?(imageName: String, readOnly: Bool = true) {
        print("imageName:", imageName)
        imageURL = URL(fileURLWithPath: imageName, isDirectory: false)
        guard let data = try? Data(contentsOf: imageURL) else {
            print("Cant load")
            return nil
        }
        self.data = data
        heads = 2
        tracksPerHead = 80
        sectorsPerTrack = 9
        let totalSize = heads * tracksPerHead * sectorsPerTrack * sectorSize
        guard totalSize == data.count else {
            print("Image size != floppy size")
            return nil
        }
        isReadOnly = !FileManager.default.isWritableFile(atPath: imageName)
    }

    var totalSectors: Int { (data.count + sectorSize - 1) / sectorSize }

    func trackAndSectorFrom(cx: UInt16) -> (Int, Int) {
        let sector = Int(cx) & 0x3f
        let track = Int(cx) >> 8 | (Int(cx & 0xc0) << 10)
        return (track, sector)
    }


    func logicalSector(cx: UInt16, dh: UInt8) -> Int? {
        let head = Int(dh)    // DH = head
        let sector = Int(cx) & 0x3f
        let track = Int(cx) >> 8 | (Int(cx & 0xc0) << 10)
        // print("logicalSector: head: \(head) track: \(track) sector: \(sector)")
        guard sector > 0 && sector <= sectorsPerTrack && track < tracksPerHead && head < heads else {
            return nil
        }
        let logical = (sector - 1) + (head * sectorsPerTrack) + (track * sectorsPerTrack * heads)
        // print("logical: \(logical)")
        return logical
    }


    struct SectorOperation {
        let startSector: Int
        let sectorCount: Int
        let bufferOffset: Int
        let bufferSize: Int
    }

    // Used by BIOS calls for reading/writing/verifying sectors
    // Converts al, cx, dx, es:bx into a SectorOperation and validates input
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
        guard startSector + sectorCount <= self.totalSectors else {
            return .failure(.invalidNumberOfSectors)
        }
        let offset = Int(vcpu.registers.es.base) + bx
        //print("Copying \(size) bytes to 0x\(String(offset, radix: 16))")
        let operation = SectorOperation(startSector: startSector, sectorCount: sectorCount, bufferOffset: offset, bufferSize: size)
        return .success(operation)
    }


    func readSectors(into buffer: UnsafeMutableRawBufferPointer, fromSector sector: Int, count: Int) -> Status {
        let offset = sector * sectorSize
        let size = count * sectorSize
        let range = offset..<(offset + size)
        assert(size == buffer.count)
        data.copyBytes(to: buffer, from: range)
        return .ok
    }


    func verifySectors(in buffer: UnsafeRawBufferPointer, toSector sector: Int, count: Int) -> Status {
        let offset = sector * sectorSize
        let size = count * sectorSize
        let range = offset..<(offset + size)
        assert(size == buffer.count)
        let dataInMemory = Data(buffer)
        if data[range] == dataInMemory {
            return .ok
        } else {
            return .dataError
        }
    }


    func writeSectors(from buffer: UnsafeRawBufferPointer, toSector sector: Int, count: Int) -> Status {
        let offset = sector * sectorSize
        let size = count * sectorSize
        let range = offset..<(offset + size)
        assert(size == buffer.count)
        data.replaceSubrange(range, with: buffer)
        return .ok
    }


    func setCurrentTrack(_ track: Int) -> Status {
        if track < tracksPerHead {
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
