// Pulls stills out of a video to check it before publishing.
//   swift frames.swift VIDEO.mp4 OUT_DIR 1.5 6 11
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let gen = AVAssetImageGenerator(asset: asset)
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero
for t in args.dropFirst(3) {
    let image = try gen.copyCGImage(at: CMTime(seconds: Double(t)!, preferredTimescale: 600), actualTime: nil)
    let url = URL(fileURLWithPath: args[2]).appendingPathComponent("frame-\(t).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print(url.path)
}
