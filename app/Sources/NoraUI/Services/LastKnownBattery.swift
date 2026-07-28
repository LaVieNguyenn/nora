import Foundation

/// Remembers the last battery reading for each device.
///
/// Bluetooth accessories stop reporting entirely once they disconnect, so
/// without this the AirPods row would vanish the moment they go back in the
/// case — exactly when you want to know what they were sitting at.
enum LastKnownBattery {
    struct Reading {
        let percent: Int?
        let left: Int?
        let right: Int?
        let caseLevel: Int?
        let date: Date
    }

    private static let key = "lastKnownBattery"
    /// Older than this and the number is misleading rather than useful.
    private static let maxAge: TimeInterval = 60 * 60 * 24 * 3

    static func store(_ device: DeviceBattery) {
        // Build from non-nil values only. Writing `optional as Any` puts a
        // wrapped Optional in the dictionary — it is not `NSNull`, so filtering
        // on `is NSNull` never caught it, and UserDefaults raised
        // NSInvalidArgumentException ("attempt to insert non-property list
        // object") the first time a device reported a partial reading, killing
        // the app at launch.
        var entry: [String: Any] = ["date": Date().timeIntervalSince1970]
        if let percent = device.percent { entry["percent"] = percent }
        if let left = device.left { entry["left"] = left }
        if let right = device.right { entry["right"] = right }
        if let caseLevel = device.caseLevel { entry["case"] = caseLevel }

        var all = raw()
        all[device.id] = entry
        UserDefaults.standard.set(all, forKey: key)
    }

    static func load(id: String) -> Reading? {
        guard let entry = raw()[id],
              let timestamp = entry["date"] as? TimeInterval
        else { return nil }

        let date = Date(timeIntervalSince1970: timestamp)
        guard Date().timeIntervalSince(date) < maxAge else { return nil }

        let reading = Reading(
            percent: entry["percent"] as? Int,
            left: entry["left"] as? Int,
            right: entry["right"] as? Int,
            caseLevel: entry["case"] as? Int,
            date: date
        )
        // An entry with a timestamp but no levels tells us nothing.
        guard reading.percent != nil || reading.left != nil || reading.right != nil
        else { return nil }
        return reading
    }

    private static func raw() -> [String: [String: Any]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Any]] ?? [:]
    }
}
