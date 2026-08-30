import Foundation

public enum Fixture {
    public static func text(_ name: String) -> String {
        String(data: data(name), encoding: .utf8) ?? ""
    }

    public static func data(_ name: String) -> Data {
        (try? Data(contentsOf: url(name))) ?? Data()
    }

    public static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
            ?? Bundle.module.url(
                forResource: (name as NSString).deletingPathExtension,
                withExtension: (name as NSString).pathExtension
            )!
    }
}
