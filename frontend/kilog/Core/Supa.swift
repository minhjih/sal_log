import Foundation
import Supabase

/// Supabase 프로젝트 연결 정보.
/// 배포 시 본인 프로젝트의 URL / anon key로 교체하세요.
/// anon key는 공개되어도 되는 키이며, 실제 접근 제어는 전부 RLS가 담당합니다.
enum SupabaseConfig {
    static let url = URL(string: "https://YOUR-PROJECT-REF.supabase.co")!
    static let anonKey = "YOUR-ANON-KEY"
    static let redirectURL = URL(string: "app.kilog://auth-callback")!
}

enum Supa {
    static let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey,
        options: .init(
            db: .init(encoder: postgresEncoder, decoder: postgresDecoder),
            auth: .init(redirectToURL: SupabaseConfig.redirectURL)
        )
    )

    /// Postgres timestamptz(소수점 초 유무 모두)와 date를 관대하게 파싱
    static let postgresDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let raw = try d.singleValueContainer().decode(String.self)
            for formatter in [isoFractional, isoPlain] {
                if let date = formatter.date(from: raw) { return date }
            }
            if let date = dateOnly.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: d.codingPath, debugDescription: "Unparsable date: \(raw)"
            ))
        }
        return decoder
    }()

    static let postgresEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, e in
            var c = e.singleValueContainer()
            try c.encode(isoFractional.string(from: date))
        }
        return encoder
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
