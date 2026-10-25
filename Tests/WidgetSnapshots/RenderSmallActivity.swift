import AppKit
import SwiftUI

// Compile this with Widget/CaptionSmallActivityView.swift on macOS. This renders
// the actual small-family view at constrained sizes, without an ActivityKit host.
@main
@MainActor
struct RenderSmallActivity {
    static func main() throws {
        let directory = URL(fileURLWithPath:CommandLine.arguments.dropFirst().first ?? "/tmp/caption-small-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let japanese = "月曜日の朝 憂鬱な気持ちも 君と会う日を思い浮かべれば"
        let nextJapanese = "いつもの道に優しい風が吹き 心弾ませ今日が始まるよ"
        let samples: [(String, CGFloat, CGFloat, String, String, DynamicTypeSize, LayoutDirection)] = [
            ("japanese-roomy", 212, 128, japanese, nextJapanese, .large, .leftToRight),
            ("japanese-narrow", 160, 96, japanese, nextJapanese, .large, .leftToRight),
            ("latin-short", 212, 80, "Can my soul", "Find its way back home", .large, .leftToRight),
            ("latin-long", 212, 80, "A longer current lyric that wraps inside the available card", "The next line stays below it", .large, .leftToRight),
            ("without-next", 160, 64, japanese, "", .large, .leftToRight),
            ("large-type", 212, 96, japanese, nextJapanese, .accessibility1, .leftToRight),
            ("rtl", 212, 96, "هذه كلمات الأغنية الحالية", "وهذه كلمات السطر التالي", .large, .rightToLeft),
            ("tiny-height", 160, 38, "Can my soul", "Find its way back home", .large, .leftToRight),
        ]
        for (name, width, height, current, next, type, direction) in samples {
            let view = CaptionSmallActivityView(currentLine: current, nextLine: next)
                .environment(\.dynamicTypeSize, type)
                .environment(\.layoutDirection, direction)
                .environment(\.colorScheme, .dark)
                .frame(width: width, height: height)
                .background(Color.black)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                fatalError("Unable to render \(name)")
            }
            precondition(image.width == Int(width * 3) && image.height == Int(height * 3))
            try data.write(to: directory.appendingPathComponent(name + ".png"))
        }
        print("Rendered \(samples.count) production-view snapshots in \(directory.path)")
    }
}
