import Foundation

public enum Geo {
    static let earthRadiusNM = 3440.065

    public static func distanceNM(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusNM * asin(min(1, sqrt(h)))
    }

    /// Great-circle destination from `origin` along `trackDeg` for `distanceNM`.
    public static func project(_ origin: Coordinate, trackDeg: Double, distanceNM: Double) -> Coordinate {
        let d = distanceNM / earthRadiusNM
        let brg = trackDeg * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brg))
        let lon2 = lon1 + atan2(sin(brg) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
        return Coordinate(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    /// East/north offset of `point` from `origin`, in nautical miles (flat-earth; fine at airport scale).
    public static func offsetNM(from origin: Coordinate, to point: Coordinate) -> (east: Double, north: Double) {
        let north = (point.latitude - origin.latitude) * 60
        let east = (point.longitude - origin.longitude) * 60 * cos(origin.latitude * .pi / 180)
        return (east, north)
    }
}
