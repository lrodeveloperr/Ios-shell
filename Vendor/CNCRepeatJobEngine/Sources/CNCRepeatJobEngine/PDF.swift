#if canImport(UIKit)
import UIKit

public enum BenchPDF {
    public static func handoff(_ run: Run, setup: Setup) -> Data {
        let text = BenchExport.handoff(run, setup: setup)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            let font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
            let inset: CGFloat = 40
            var y: CGFloat = inset
            context.beginPage()
            for line in text.components(separatedBy: "\n") {
                let candidate = line.isEmpty ? " " : line
                let box = (candidate as NSString).boundingRect(
                    with: CGSize(width: 612 - inset * 2, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
                let height = max(15, ceil(box.height) + 2)
                if y + height > 792 - inset { context.beginPage(); y = inset }
                (candidate as NSString).draw(in: CGRect(x: inset, y: y, width: 612 - inset * 2, height: height),
                                             withAttributes: attributes)
                y += height
            }
        }
    }
}
#endif
