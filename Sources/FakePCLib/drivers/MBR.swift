//
//  MBR.swift
//  FakePC
//
//  Created by Simon Evans on 04/04/2021.
//  Copyright © 2021 Simon Evans. All rights reserved.
//
//  MBR (Master Boot Record), used to access partition information
//

import Foundation


extension MasterBootRecord {
    struct Partition {
        let status: UInt8
        let firstSectorCHS: (track: UInt16, head: UInt8, sector: UInt8)
        let partitionType: UInt8
        let lastSectorCHS: (track: UInt16, head: UInt8, sector: UInt8)
        let startSectorLBA: UInt32
        let sectorCount: UInt32


        init(_ data: Data) {
            precondition(data.count == 16)
            let index = data.startIndex
            status = data[index]

            do {
                let (track, sector) = Disk.trackAndSectorFrom(cx: data[index + 2 ... index + 3].readLSB16())
                firstSectorCHS = (track: UInt16(track), head: data[index + 1], sector: UInt8(sector))
            }
            partitionType = data[index + 4]

            do {
                let (track, sector) = Disk.trackAndSectorFrom(cx: data[index + 6 ... index + 7].readLSB16())
                lastSectorCHS = (track: UInt16(track), head: data[index + 5], sector: UInt8(sector))
            }

            startSectorLBA = data[index + 7 ... index + 11].readLSB32()
            sectorCount = data[index + 12 ... index + 15].readLSB32()
        }
    }

    struct Partitions: RandomAccessCollection {
        typealias Element = Partition
        typealias Index = Int
        let startIndex = 0
        let endIndex =  4
        let count = 4

        func index(after i: Int) -> Int { i + 1 }

        private let partitions: (Partition, Partition, Partition, Partition)
         subscript(index: Int) -> Partition {
            get {
                switch index {
                    case 0: return partitions.0
                    case 1: return partitions.1
                    case 2: return partitions.2
                    case 3: return partitions.3
                    default: fatalError()
                }
            }
        }

        init(_ data: Data) {
            let index = data.startIndex
            partitions = (
                Partition(data[index + 0 ... index + 15]),
                Partition(data[index + 16 ... index + 31]),
                Partition(data[index + 32 ... index + 47]),
                Partition(data[index + 48 ... index + 63])
            )
        }
    }
}

struct MasterBootRecord {
    let partitions: Partitions

    init?(_ data: Data) {
        precondition(data.count == 512)

        let index = data.startIndex
        // Check boot signature at end 0x55AA
        guard data[index + 510] == 0x55, data[index + 511] == 0xAA else { return nil }
        partitions = Partitions(data[index + 446 ... index + 509])
    }
}
