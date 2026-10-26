import ContentKit
import SwiftUI

struct ContentImageView: View {
    #if canImport(UIKit)
        typealias PlatformImage = UIImage
    #else
        typealias PlatformImage = NSImage
    #endif

    let run: Run
    var maxWidth: CGFloat

    /// 源页用 px 标注尺寸，按 96dpi 折算成 pt；没标注就铺满可用宽度。
    private func displayWidth(for image: ContentImageView.PlatformImage) -> CGFloat {
        let scale: CGFloat = 0.75
        if let height = run.h, height > 0, image.size.height > 0 {
            let width = CGFloat(height) * scale * image.size.width / image.size.height
            return min(width, maxWidth)
        }
        if let width = run.w, width > 0 {
            return min(CGFloat(width) * scale, maxWidth)
        }
        return maxWidth
    }

    var body: some View {
        #if canImport(UIKit)
            if let image = Self.load(run.img) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displayWidth(for: image))
                    .frame(maxWidth: .infinity, alignment: run.align == "right" ? .trailing : .leading)
                    .clipShape(.rect(cornerRadius: 4))
                    .accessibilityLabel(run.alt?.isEmpty == false ? run.alt! : "插图")
            }
        #else
            if let image = Self.load(run.img) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displayWidth(for: image))
                    .frame(maxWidth: .infinity, alignment: run.align == "right" ? .trailing : .leading)
                    .clipShape(.rect(cornerRadius: 4))
            }
        #endif
    }

    /// 语料内路径在打包时被拍平成 `目录_文件`，两端用同一个变换。
    static func bundleName(for path: String) -> String {
        path.replacingOccurrences(of: "/", with: "_")
    }

    #if canImport(UIKit)
        static func load(_ path: String?) -> UIImage? {
            guard let path else { return nil }
            guard let url = Bundle.main.url(forResource: bundleName(for: path), withExtension: nil)
            else { return nil }
            return UIImage(contentsOfFile: url.path)
        }
    #else
        static func load(_ path: String?) -> NSImage? {
            guard let path else { return nil }
            guard let url = Bundle.main.url(forResource: bundleName(for: path), withExtension: nil)
            else { return nil }
            return NSImage(contentsOf: url)
        }
    #endif
}
