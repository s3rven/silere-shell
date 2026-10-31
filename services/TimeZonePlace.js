.pragma library

// the system time zone's principal city, read from the tz database's own tables: the
// place is coarse, but nothing leaves the machine to find it. Prints "<ISO 6709>\t<zone>"
var script =
    "tz=\"$(timedatectl show -p Timezone --value 2>/dev/null)\"; " +
    "[ -z \"$tz\" ] && tz=\"$(readlink -f /etc/localtime 2>/dev/null | sed -n 's#.*/zoneinfo/##p')\"; " +
    "[ -z \"$tz\" ] && [ -r /etc/timezone ] && tz=\"$(cat /etc/timezone)\"; " +
    "[ -z \"$tz\" ] && exit 0; " +
    // the tables list only canonical zones; an alias like Asia/Calcutta would find no city
    "for _ in 1 2 3; do " +
    "  l=\"$(awk -v z=\"$tz\" '$1==\"L\" && $3==z {print $2; exit}' /usr/share/zoneinfo/tzdata.zi 2>/dev/null)\"; " +
    "  [ -n \"$l\" ] && [ \"$l\" != \"$tz\" ] || break; tz=\"$l\"; " +
    "done; " +
    "for f in /usr/share/zoneinfo/zone1970.tab /usr/share/zoneinfo/zone.tab; do " +
    "  [ -r \"$f\" ] || continue; " +
    "  c=\"$(awk -v z=\"$tz\" 'BEGIN{FS=\"\\t\"} $0 !~ /^#/ && $3==z {print $2; exit}' \"$f\")\"; " +
    "  [ -n \"$c\" ] && { printf '%s\\t%s\\n' \"$c\" \"$tz\"; break; }; " +
    "done"

// ±DDMM[SS]±DDDMM[SS], as zone1970.tab writes it
function parseCoord(s) {
    var m = /^([+-]\d{2})(\d{2})(\d{2})?([+-]\d{3})(\d{2})(\d{2})?$/.exec(String(s || "").trim())
    if (!m) return null
    var latDeg = Math.abs(Number(m[1])), latMin = Number(m[2]), latSec = m[3] ? Number(m[3]) : 0
    var lonDeg = Math.abs(Number(m[4])), lonMin = Number(m[5]), lonSec = m[6] ? Number(m[6]) : 0
    if (latMin >= 60 || lonMin >= 60 || latSec >= 60 || lonSec >= 60
            || latDeg > 90 || lonDeg > 180
            || (latDeg === 90 && (latMin > 0 || latSec > 0))
            || (lonDeg === 180 && (lonMin > 0 || lonSec > 0))) return null
    var latSign = m[1].charAt(0) === "-" ? -1 : 1
    var lonSign = m[4].charAt(0) === "-" ? -1 : 1
    return {
        lat: latSign * (latDeg + latMin / 60 + latSec / 3600),
        lon: lonSign * (lonDeg + lonMin / 60 + lonSec / 3600)
    }
}

// America/Argentina/Buenos_Aires reads as Buenos Aires
function placeName(zone) {
    var parts = String(zone || "").trim().split("/")
    return parts[parts.length - 1].replace(/_/g, " ")
}

// split one line of the script's output
function parseLine(text) {
    var fields = String(text || "").trim().split("\t")
    var coord = parseCoord(fields[0])
    if (!coord) return null
    coord.zone = fields.length > 1 ? fields[1] : ""
    return coord
}
