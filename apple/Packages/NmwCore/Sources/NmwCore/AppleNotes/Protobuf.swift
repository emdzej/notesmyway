//
//  Protobuf.swift
//  NmwCore
//
//  Just enough protobuf to read Apple Notes' note bodies: varints and
//  length-delimited fields, by field number. Unknown fields are skipped.
//

import Foundation

struct ProtoField {
    let number: Int
    /// The value of a varint field.
    let varint: UInt64
    /// The bytes of a length-delimited field (string, bytes, message).
    let bytes: Data

    var int: Int { Int(truncatingIfNeeded: varint) }
    var string: String { String(decoding: bytes, as: UTF8.self) }
    var message: [ProtoField] { (try? ProtoReader.fields(of: bytes)) ?? [] }
}

enum ProtoReader {
    struct Malformed: Error {}

    /// The top-level fields of a message, in order.
    static func fields(of data: Data) throws -> [ProtoField] {
        let bytes = [UInt8](data)
        var fields: [ProtoField] = []
        var i = 0
        while i < bytes.count {
            let key = try varint(bytes, &i)
            let number = Int(key >> 3)
            switch key & 7 {
            case 0:
                fields.append(ProtoField(number: number, varint: try varint(bytes, &i), bytes: Data()))
            case 1:
                guard i + 8 <= bytes.count else { throw Malformed() }
                i += 8
            case 2:
                let length = Int(try varint(bytes, &i))
                guard length >= 0, i + length <= bytes.count else { throw Malformed() }
                fields.append(ProtoField(number: number, varint: 0, bytes: Data(bytes[i..<(i + length)])))
                i += length
            case 5:
                guard i + 4 <= bytes.count else { throw Malformed() }
                i += 4
            default:
                throw Malformed()
            }
        }
        return fields
    }

    private static func varint(_ bytes: [UInt8], _ i: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while i < bytes.count {
            let byte = bytes[i]
            i += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
            if shift > 63 { throw Malformed() }
        }
        throw Malformed()
    }
}

extension Array where Element == ProtoField {
    func first(_ number: Int) -> ProtoField? { first { $0.number == number } }
    func all(_ number: Int) -> [ProtoField] { filter { $0.number == number } }
}
