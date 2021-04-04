//
//  iso9660.swift
//  FakePC
//
//  Created by Simon Evans on 02/04/2021.
//  Copyright © 2021 Simon Evans. All rights reserved.
//
//  Read an ISO9660 CD-ROM

import Foundation

typealias DateString = String

enum ISO9660Error: Error {
    case invalidIdentifier(String)
    case invalideVolumeDescriptorVersion(UInt8)
}

enum VolumeDescriptorTypeCode {
    case bootRecord
    case primaryVolumeDescriptor
    case supplementaryVolumeDescriptor
    case volumePartitionDescriptor
    case reserved(UInt8)
    case volumeDescriptorSetTerminator

    init(_ rawValue: UInt8) {
        switch rawValue {
            case 0: self = .bootRecord
            case 1: self = .primaryVolumeDescriptor
            case 2: self = .supplementaryVolumeDescriptor
            case 3: self = .volumePartitionDescriptor
            case 255: self = .volumeDescriptorSetTerminator
            default: self = .reserved(rawValue)
        }
    }
}

struct ISO9660 {
    let fileHandle: FileHandle
    let totalSize: UInt64
    let sectorCount: UInt64
    let sectorSize = 2048

    init(fileHandle: FileHandle, totalSize: UInt64) {
        self.fileHandle = fileHandle
        self.totalSize = totalSize
        sectorCount = (totalSize + UInt64(sectorSize) - 1) / UInt64(sectorSize)
    }

    func read(sector: UInt64) throws -> Data {
        try fileHandle.seek(toOffset: sector * UInt64(sectorSize))
        return fileHandle.readData(ofLength: sectorSize)
    }

    func volumeDescriptor(sectorData: Data) throws -> VolumeDescriptorTypeCode {
        let volumeDescriptor = VolumeDescriptorTypeCode(sectorData[0])
        let identifier = ISO9660.readString(sectorData[1...5])
        guard identifier == "CD001" else { throw ISO9660Error.invalidIdentifier(identifier) }
        let version = sectorData[6]
        guard version == 1 else { throw ISO9660Error.invalideVolumeDescriptorVersion(version) }
        return volumeDescriptor
    }

    func primaryVolumeDescriptor() -> PrimaryVolumeDescriptor? {
        do {
            let sector = try read(sector: 16)
            return PrimaryVolumeDescriptor(sectorData: sector)
        } catch {
            fatalError("\(error)")
        }
    }

    func bootableEntry() -> BootCatalog.DefaultEntry? {
        do {
            guard let bootRecord = BootRecord(sectorData: try read(sector: 17)) else { return nil }
            let catalog = try read(sector: UInt64(bootRecord.catalogLBA))
            guard BootCatalog.ValidationEntry(entryData: catalog[0...0x1f]) != nil else { return nil }
            guard let defaultEntry = BootCatalog.DefaultEntry(entryData: catalog[0x20...0x3f]) else { return nil }
            guard defaultEntry.bootIndicator, .noEmulation == defaultEntry.bootMedia, defaultEntry.systemType == 0x0 else {
                return nil
            }
            return defaultEntry
        } catch {
            logger.error("Error reading from CDROM: \(error)")
            return nil
        }
    }
}

// Methods to interpet ISO9660 data structures (String, UInt16, UInt32, Date)
extension ISO9660 {
    private static func readString(_ data: Data) -> String {
        var endIndex = data.endIndex
        while endIndex > data.startIndex && data[endIndex - 1] == UInt8(ascii: " ") {
            endIndex -= 1
        }
        var string = ""
        for index in data.startIndex..<endIndex {
            var ch = data[index]
            if ch == 0 { break }
            if ch > 128 { ch = 63 } // replace non-ascii with '?'
            string.append(Character(UnicodeScalar(ch)))
        }
        return string
    }

    fileprivate static func readStringA(_ data: Data) -> String { readString(data) }
    fileprivate static func readStringD(_ data: Data) -> String { readString(data) }

    fileprivate static func readLSB16(_ data: Data) -> UInt16 {
        let index = data.startIndex
        return UInt16(data[index + 0]) | UInt16(data[index + 1]) << 8
    }

    fileprivate static func readLSB32(_ data: Data) -> UInt32 {
        let index = data.startIndex
        return UInt32(data[index + 0]) | UInt32(data[index + 1]) << 8 | UInt32(data[index + 2]) << 16 | UInt32(data[index + 3]) << 24
    }

    fileprivate static func readDateTime(_ data: Data) -> DateString {
        let index = data.startIndex
        return readStringD(data[index...(index + 15)])
    }
}


extension ISO9660 {
    struct PrimaryVolumeDescriptor {
        let volumeDescriptorType: VolumeDescriptorTypeCode
        let standardIdentifier: String
        let volumeDescriptorVersion: UInt8
        let systemIdentifier: String
        let volumeIdentifier: String
        let volumeSpaceSize: UInt32
        let volumeSetSize: UInt16
        let volumeSequenceNumber: UInt16
        let logicalBlockSize: UInt16
        let pathTableSize: UInt32
        let locationOfPathTable: UInt32
        let locationOfOptionalTathTable: UInt32
        // Directory record for Root Directory
        let volumeSetIdentifier: String
        let publisherIdentifier: String
        let dataPreparerIdentifier: String
        let applicationIdentifier: String
        let copyrightFileIdentifier: String
        let abstractFileIdentifier: String
        let bibliographicFileIdentifer: String
        let volumeCreationDate: DateString
        let volumeModificationDate: DateString
        let volumeExpirationDate: DateString
        let volumeEffectiveDate: DateString
        let fileStructureVersion: UInt8


        init?(sectorData: Data) {
            guard sectorData.count == 2048 else { return nil }
            volumeDescriptorType = VolumeDescriptorTypeCode(sectorData[0])
            standardIdentifier = ISO9660.readStringA(sectorData[1...5])
            volumeDescriptorVersion = sectorData[6]
            guard sectorData[7] == 0 else { return nil }
            systemIdentifier = ISO9660.readStringA(sectorData[8...39])
            volumeIdentifier = ISO9660.readStringD(sectorData[40...71])
            volumeSpaceSize = sectorData[80...83].readLSB32()
            volumeSetSize = sectorData[120...121].readLSB16()
            volumeSequenceNumber = sectorData[124...125].readLSB16()
            logicalBlockSize = sectorData[128...129].readLSB16()
            pathTableSize = sectorData[132...135].readLSB32()
            locationOfPathTable = sectorData[140...143].readLSB32()
            locationOfOptionalTathTable = sectorData[144...147].readLSB32()
            volumeSetIdentifier = ISO9660.readStringD(sectorData[190...317])
            publisherIdentifier = ISO9660.readStringA(sectorData[318...445])
            dataPreparerIdentifier = ISO9660.readStringA(sectorData[446...573])
            applicationIdentifier = ISO9660.readStringA(sectorData[574...701])
            copyrightFileIdentifier = ISO9660.readStringD(sectorData[702...739])
            abstractFileIdentifier = ISO9660.readStringD(sectorData[740...775])
            bibliographicFileIdentifer = ISO9660.readStringD(sectorData[776...812])
            volumeCreationDate = ISO9660.readDateTime(sectorData[813...829])
            volumeModificationDate = ISO9660.readDateTime(sectorData[830...847])
            volumeExpirationDate = ISO9660.readDateTime(sectorData[847...864])
            volumeEffectiveDate = ISO9660.readDateTime(sectorData[864...880])
            fileStructureVersion = sectorData[881]
        }
    }
}


extension ISO9660 {
    struct BootRecord {
        let bootSystemIdentifier: String
        let bootIdentifier: String
        let catalogLBA: UInt32

        init?(sectorData: Data) {
            guard sectorData.count == 2048 else { return nil }
            bootSystemIdentifier = ISO9660.readStringA(sectorData[7...38])
            bootIdentifier = ISO9660.readStringA(sectorData[39...71])
            catalogLBA = ISO9660.readLSB32(sectorData[71...74])
        }
    }

    struct BootCatalog {

        enum BootMediaType {
            case noEmulation
            case diskette1_2
            case diskette1_44
            case diskette2_88
            case hardDisk
            case reserved

            init?(_ rawValue: UInt8) {
                switch rawValue & 0xf {
                    case 0: self = .noEmulation
                    case 1: self = .diskette1_2
                    case 2: self = .diskette1_44
                    case 3: self = .diskette2_88
                    case 4: self = .hardDisk
                    default: return nil
                }
            }
        }

        struct ValidationEntry {
            let platform: UInt8
            let manufacturer: String

            init?(entryData: Data) {
                // Read and validate entry
                let index = entryData.startIndex
                guard entryData[index] == 1 else { return nil }
                platform = entryData[index + 1]
                guard entryData[index + 2] == 0, entryData[index + 3] == 0 else { return nil }
                manufacturer = ISO9660.readStringA(entryData[index + 4 ... index + 0x1b])
                //let checksum = entryData.reduce(0, &+)
                //guard checksum == 0 else { return nil }
                guard entryData[0x1e] == 0x55, entryData[0x1f] == 0xAA else { return nil }
            }
        }

        struct DefaultEntry {
            let bootIndicator: Bool
            let bootMedia: BootMediaType
            let loadSegment: UInt16
            let systemType: UInt8
            let sectorCount: UInt16
            let startSectorLBA: UInt32

            init?(entryData: Data) {
                let index = entryData.startIndex
                switch entryData[index] {
                    case 0: bootIndicator = false
                    case 0x88: bootIndicator = true
                    default: return nil
                }
                guard let media = BootMediaType(entryData[index + 1]) else { return nil }
                bootMedia = media
                loadSegment = ISO9660.readLSB16(entryData[index + 2 ... index + 3])
                systemType = entryData[index + 4]
                guard entryData[index + 5] == 0 else { return nil }
                sectorCount = ISO9660.readLSB16(entryData[index + 6 ... index + 7])
                startSectorLBA = ISO9660.readLSB32(entryData[index + 8 ... index + 0xb])
            }
        }
    }
}
