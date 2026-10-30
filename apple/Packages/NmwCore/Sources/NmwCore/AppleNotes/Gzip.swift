//
//  Gzip.swift
//  NmwCore
//
//  Apple Notes stores note bodies gzipped. Foundation inflates raw deflate
//  (`.zlib`); this strips the gzip header and trailer around it.
//

import Foundation

enum Gzip {
    struct Invalid: Error {}

    static func isGzip(_ data: Data) -> Bool {
        data.count > 18 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else { throw Invalid() }
        let flags = bytes[3]
        var i = 10
        if flags & 0x04 != 0 {   // FEXTRA
            guard i + 2 <= bytes.count else { throw Invalid() }
            i += 2 + (Int(bytes[i]) | (Int(bytes[i + 1]) << 8))
        }
        if flags & 0x08 != 0 { while i < bytes.count, bytes[i] != 0 { i += 1 }; i += 1 }   // FNAME
        if flags & 0x10 != 0 { while i < bytes.count, bytes[i] != 0 { i += 1 }; i += 1 }   // FCOMMENT
        if flags & 0x02 != 0 { i += 2 }   // FHCRC
        guard i < bytes.count - 8 else { throw Invalid() }
        let deflated = Data(bytes[i..<(bytes.count - 8)]) as NSData
        guard let inflated = try? deflated.decompressed(using: .zlib) else { throw Invalid() }
        return inflated as Data
    }
}
