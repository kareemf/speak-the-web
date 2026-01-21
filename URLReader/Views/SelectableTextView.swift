import SwiftUI

private final class WrappingTextView: UITextView {
    override func layoutSubviews() {
        super.layoutSubviews()
        if textContainer.size.width != bounds.width {
            textContainer.size = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
        }
    }
}

struct SelectableTextView: UIViewRepresentable {
    let text: String
    let width: CGFloat
    @Binding var height: CGFloat
    let font: UIFont
    let textColor: UIColor
    let lineSpacing: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let textView = WrappingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.attributedText?.string != text {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = lineSpacing
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]
            uiView.attributedText = NSAttributedString(string: text, attributes: attributes)
        }

        let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let fittingSize = uiView.sizeThatFits(targetSize)
        if height != fittingSize.height {
            DispatchQueue.main.async {
                height = fittingSize.height
            }
        }
    }
}
