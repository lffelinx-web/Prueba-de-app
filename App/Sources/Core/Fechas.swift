import Foundation

/// Dates in the database are local calendar days written as "yyyy-MM-dd".
enum Fecha {
    static var calendario: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static let formatoISO: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Start of the given day, or nil for empty or malformed text.
    static func dia(_ texto: String?) -> Date? {
        guard let texto, texto.count >= 10 else { return nil }
        formatoISO.timeZone = .current
        guard let fecha = formatoISO.date(from: String(texto.prefix(10))) else { return nil }
        return calendario.startOfDay(for: fecha)
    }

    static func iso(_ fecha: Date) -> String {
        formatoISO.timeZone = .current
        return formatoISO.string(from: fecha)
    }

    static var hoy: Date { calendario.startOfDay(for: Date()) }
    static var hoyISO: String { iso(hoy) }

    static func sumar(dias: Int, a fecha: Date) -> Date {
        calendario.date(byAdding: .day, value: dias, to: fecha) ?? fecha
    }

    /// Whole calendar days from `desde` to `hasta` (negative when `hasta` is earlier).
    static func dias(desde: Date, hasta: Date) -> Int {
        calendario.dateComponents([.day], from: calendario.startOfDay(for: desde), to: calendario.startOfDay(for: hasta)).day ?? 0
    }

    static func mismoDia(_ a: Date, _ b: Date) -> Bool {
        calendario.isDate(a, inSameDayAs: b)
    }

    /// "dd/MM/yyyy", or "—" when there is no date.
    static func corta(_ fecha: Date?) -> String {
        guard let fecha else { return "—" }
        let partes = calendario.dateComponents([.day, .month, .year], from: fecha)
        return String(format: "%02d/%02d/%04d", partes.day ?? 0, partes.month ?? 0, partes.year ?? 0)
    }

    static func corta(_ texto: String?) -> String {
        corta(dia(texto))
    }

    static func larga(_ fecha: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "EEEE, d 'de' MMMM 'de' y"
        return formatter.string(from: fecha)
    }

    /// Timestamps written by the web app with `new Date().toISOString()`.
    static func timestampISO(_ fecha: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: fecha)
    }

    /// "12 de mayo, 2026 — 14:35", as the web app shows the macropesos update time.
    static func actualizacion(_ texto: String?) -> String {
        guard let texto else { return "sin registrar" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let fecha = formatter.date(from: texto) ?? ISO8601DateFormatter().date(from: texto) else { return "sin registrar" }
        let salida = DateFormatter()
        salida.locale = Locale(identifier: "es_MX")
        salida.dateFormat = "d 'de' MMMM, y '—' HH:mm"
        return salida.string(from: fecha)
    }

    /// Milliseconds since 1970, the unit of `ts` fields and generated ids.
    static func milisegundos(_ fecha: Date = Date()) -> Int64 {
        Int64((fecha.timeIntervalSince1970 * 1000).rounded())
    }
}

enum Dinero {
    static func texto(_ valor: Double?) -> String {
        guard let valor else { return "—" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "$" + (formatter.string(from: NSNumber(value: valor)) ?? String(valor))
    }
}

enum Identificador {
    /// Same shape as the web app's `Date.now().toString()`.
    static func nuevo() -> String { String(Fecha.milisegundos()) }

    /// Ids for prospects created from references: timestamp + "_r" + 3 base-36 characters.
    static func referencia() -> String { nuevo() + "_r" + aleatorio(3) }

    static func aleatorio(_ longitud: Int) -> String {
        let alfabeto = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return String((0..<longitud).map { _ in alfabeto.randomElement()! })
    }
}
