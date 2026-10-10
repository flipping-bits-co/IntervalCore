import Foundation

/// UUIDs derived from a name, identical on every launch and device. Bundled tracks and
/// templates use them so enrolments, synced snapshots and `TrackRef` block tags keep
/// pointing at the same things after an app update. FNV-1a, like `StructureHash`, because
/// `Hasher` is seeded per process.
public enum StableUUID {

    public static func make(_ name: String) -> UUID {
        let high = fnv(name, basis: 0xcbf2_9ce4_8422_2325)
        let low = fnv(name, basis: 0x6c62_272e_07bb_0142)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: high >> (56 - 8 * i))
            bytes[8 + i] = UInt8(truncatingIfNeeded: low >> (56 - 8 * i))
        }
        // RFC 9562 version 8 (custom) and variant bits, so it's a well-formed UUID.
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func fnv(_ string: String, basis: UInt64) -> UInt64 {
        var hash = basis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
