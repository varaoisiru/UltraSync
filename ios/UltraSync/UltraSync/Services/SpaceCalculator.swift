import Foundation

/// Native port of the computations in ultrasync/space.py: synodic moon
/// phase with true geometric illumination, JPL approximate planet
/// elements → topocentric alt/az, and the NOAA sunrise/sunset algorithm.
/// Same constants, same rounding, so standalone iOS results track the
/// Python app's.
enum SpaceCalculator {

    static let synodicMonth = 29.530588853
    /// 2000-01-06 18:14 UTC (KNOWN_NEW_MOON in space.py).
    static let knownNewMoon = Date(timeIntervalSince1970: 947_182_440)

    static let phaseNames = ["New Moon", "Waxing Crescent", "First Quarter",
                             "Waxing Gibbous", "Full Moon", "Waning Gibbous",
                             "Last Quarter", "Waning Crescent"]
    static let phaseIcons = ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]

    // MARK: Moon

    static func moonPhase(at date: Date = Date()) -> Double {
        let days = date.timeIntervalSince(knownNewMoon) / 86400.0
        let r = days.truncatingRemainder(dividingBy: synodicMonth)
        return (r < 0 ? r + synodicMonth : r) / synodicMonth
    }

    static func moonIllumination(phase: Double) -> Double {
        (1 - cos(2 * Double.pi * phase)) / 2
    }

    static func phaseIndex(_ phase: Double) -> Int {
        Int((phase + 0.0625) * 8) % 8
    }

    static func moonData(at date: Date = Date()) -> SpaceData.MoonData {
        let phase = moonPhase(at: date)
        let idx = phaseIndex(phase)
        return SpaceData.MoonData(
            phase: (phase * 10000).rounded() / 10000,
            illumination: (moonIllumination(phase: phase) * 1000).rounded() / 10,
            name: phaseNames[idx],
            icon: phaseIcons[idx])
    }

    // MARK: Sun times (NOAA algorithm, as used by space.py sun_times)

    private static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    /// (sunrise, sunset) in UTC via the NOAA worksheet algorithm;
    /// nil for polar day/night. Accurate to a couple of minutes.
    static func sunTimesUTC(on date: Date, lat: Double, lon: Double) -> (sunrise: Date, sunset: Date)? {
        let jd = julianDay(date)
        let t = (jd - 2451545.0) / 36525.0
        let geomMeanLong = (280.46646 + t * (36000.76983 + 0.0003032 * t))
            .truncatingRemainder(dividingBy: 360)
        let geomMeanAnom = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccent = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let meanLongRad = geomMeanLong * .pi / 180
        let anomRad = geomMeanAnom * .pi / 180
        let eqCenter = sin(anomRad) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * anomRad) * (0.019993 - 0.000101 * t)
            + sin(3 * anomRad) * 0.000289
        let trueLong = geomMeanLong + eqCenter
        let omega = 125.04 - 1934.136 * t
        let lambda = trueLong - 0.00569 - 0.00478 * sin(omega * .pi / 180)
        let meanObliq = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliqCorr = meanObliq + 0.00256 * cos(omega * .pi / 180)
        let declRad = asin(sin(obliqCorr * .pi / 180) * sin(lambda * .pi / 180))
        let varY = tan(obliqCorr / 2 * .pi / 180)
        let eqTime = 4 * (180 / .pi) * (varY * varY * sin(2 * meanLongRad)
            - 2 * eccent * sin(anomRad)
            + 4 * eccent * varY * varY * sin(anomRad) * cos(2 * meanLongRad)
            - 0.5 * varY * varY * varY * varY * sin(4 * meanLongRad)
            - 1.25 * eccent * eccent * sin(2 * anomRad))
        let latRad = lat * .pi / 180
        let zenith = 90.833 * .pi / 180
        let cosH = (cos(zenith) / (cos(latRad) * cos(declRad))) - tan(latRad) * tan(declRad)
        guard cosH >= -1, cosH <= 1 else { return nil }
        let haDeg = acos(cosH) * 180 / .pi
        let sunriseMin = 720 - 4 * (lon + haDeg) - eqTime
        let sunsetMin = 720 - 4 * (lon - haDeg) - eqTime
        // Build from the UTC midnight of the given date.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let utcMidnight = cal.startOfDay(for: date)
        return (utcMidnight.addingTimeInterval(sunriseMin * 60),
                utcMidnight.addingTimeInterval(sunsetMin * 60))
    }

    // MARK: Planets (JPL approximate elements, space.py _ELEMENTS)

    private struct Elements {
        let a, e, i, l, varpi, node: Double
        let da, de, di, dl, dvarpi, dnode: Double
    }

    private static let elements: [(String, Elements)] = [
        ("Mercury", Elements(a: 0.38709927, e: 0.20563593, i: 7.00497902, l: 252.25032350, varpi: 77.45779628, node: 48.33076593, da: 0.00000037, de: 0.00001906, di: -0.00594749, dl: 149472.67411175, dvarpi: 0.16047689, dnode: -0.12534081)),
        ("Venus", Elements(a: 0.72333566, e: 0.00677672, i: 3.39467605, l: 181.97909950, varpi: 131.60246718, node: 76.67984255, da: 0.00000390, de: -0.00004107, di: -0.00078890, dl: 58517.81538729, dvarpi: 0.00268329, dnode: -0.27769418)),
        ("Mars", Elements(a: 1.52371034, e: 0.09339410, i: 1.84969142, l: -4.55343205, varpi: -23.94362959, node: 49.55953891, da: 0.00001847, de: 0.00007882, di: -0.00813131, dl: 19140.30268499, dvarpi: 0.44441088, dnode: -0.29257343)),
        ("Jupiter", Elements(a: 5.20288700, e: 0.04838624, i: 1.30439695, l: 34.39644051, varpi: 14.72847983, node: 100.47390909, da: -0.00011607, de: -0.00013253, di: -0.00183714, dl: 3034.74612775, dvarpi: 0.21252668, dnode: 0.20469106)),
        ("Saturn", Elements(a: 9.53667594, e: 0.05386179, i: 2.48599187, l: 49.95424423, varpi: 92.59887831, node: 113.66242448, da: -0.00125060, de: -0.00050991, di: 0.00193609, dl: 1222.49362201, dvarpi: -0.41897216, dnode: -0.28867794)),
    ]

    private static let earth = Elements(a: 1.00000261, e: 0.01671123, i: -0.00001531, l: 100.46457166, varpi: 102.93768193, node: 0.0, da: 0.00000562, de: -0.00004392, di: -0.01294668, dl: 35999.37244981, dvarpi: 0.32327364, dnode: 0.0)

    private static func kepler(mDeg: Double, e: Double) -> Double {
        let m = (mDeg.truncatingRemainder(dividingBy: 360)) * .pi / 180
        var ecc = m
        for _ in 0..<10 {
            ecc -= (ecc - e * sin(ecc) - m) / (1 - e * cos(ecc))
        }
        return ecc
    }

    private static func helio(_ el: Elements, t: Double) -> (x: Double, y: Double, z: Double) {
        let a = el.a + el.da * t
        let e = el.e + el.de * t
        let inc = el.i + el.di * t
        let l = el.l + el.dl * t
        let varpi = el.varpi + el.dvarpi * t
        let node = el.node + el.dnode * t
        let m = l - varpi
        let w = varpi - node
        let bigE = kepler(mDeg: m, e: e)
        let xp = a * (cos(bigE) - e)
        let yp = a * sqrt(1 - e * e) * sin(bigE)
        let cosE = cos(w * .pi / 180), sinE = sin(w * .pi / 180)
        let cosI = cos(inc * .pi / 180), sinI = sin(inc * .pi / 180)
        let cosN = cos(node * .pi / 180), sinN = sin(node * .pi / 180)
        let x = (cosE * cosN - sinE * sinN * cosI) * xp + (-sinE * cosN - cosE * sinN * cosI) * yp
        let y = (cosE * sinN + sinE * cosN * cosI) * xp + (-sinE * sinN + cosE * cosN * cosI) * yp
        let z = (sinE * sinI) * xp + (cosE * sinI) * yp
        return (x, y, z)
    }

    static func planetPositions(at date: Date = Date(), lat: Double, lon: Double) -> [SpaceData.PlanetPosition] {
        let jd = julianDay(date)
        let t = (jd - 2451545.0) / 36525.0
        let earthPos = helio(earth, t: t)
        let gmst = (280.46061837 + 360.98564736629 * (jd - 2451545.0))
            .truncatingRemainder(dividingBy: 360)
        let lst = (gmst + lon).truncatingRemainder(dividingBy: 360)
        let eps = 23.439281 * .pi / 180

        return elements.map { name, el in
            let h = helio(el, t: t)
            let gx = h.x - earthPos.x, gy = h.y - earthPos.y, gz = h.z - earthPos.z
            let ecl = (atan2(gy, gx) * 180 / .pi).truncatingRemainder(dividingBy: 360)
            let eclPos = ecl < 0 ? ecl + 360 : ecl
            let eclLat = atan2(gz, hypot(gx, gy)) * 180 / .pi
            let eclRad = eclPos * .pi / 180
            let eclLatRad = eclLat * .pi / 180
            var ra = atan2(sin(eclRad) * cos(eps) - tan(eclLatRad) * sin(eps), cos(eclRad)) * 180 / .pi
            ra = ra.truncatingRemainder(dividingBy: 360)
            if ra < 0 { ra += 360 }
            let dec = asin(sin(eclLatRad) * cos(eps) + cos(eclLatRad) * sin(eps) * sin(eclRad)) * 180 / .pi
            var haDeg = (lst - ra + 180).truncatingRemainder(dividingBy: 360)
            if haDeg < 0 { haDeg += 360 }
            haDeg -= 180
            let ha = haDeg * .pi / 180
            let decR = dec * .pi / 180
            let latR = lat * .pi / 180
            let alt = asin(sin(decR) * sin(latR) + cos(decR) * cos(latR) * cos(ha)) * 180 / .pi
            var az = atan2(sin(ha), cos(ha) * sin(latR) - tan(decR) * cos(latR)) * 180 / .pi + 180
            az = az.truncatingRemainder(dividingBy: 360)
            if az < 0 { az += 360 }
            return SpaceData.PlanetPosition(
                name: name,
                altitude: (alt * 10).rounded() / 10,
                azimuth: (az * 10).rounded() / 10,
                visible: alt > 0)
        }
    }
}
