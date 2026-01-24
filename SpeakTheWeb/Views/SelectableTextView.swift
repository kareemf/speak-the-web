import SwiftUI

private final class WrappingTextView: UITextView {
    var onStartReadingFromHere: ((Int) -> Void)?
    var lastMeasuredWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        if textContainer.size.width != bounds.width {
            textContainer.size = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
        }
    }

    @objc fileprivate func startReadingFromHere(_: Any?) {
        guard selectedRange.length > 0 else { return }
        let currentText = text ?? ""
        guard let range = Range(selectedRange, in: currentText) else { return }
        let position = currentText.distance(from: currentText.startIndex, to: range.lowerBound)
        onStartReadingFromHere?(position)
    }
}

struct SelectableTextView: UIViewRepresentable {
    let text: String
    let width: CGFloat
    @Binding var height: CGFloat
    let font: UIFont
    let textColor: UIColor
    let lineSpacing: CGFloat
    var onStartReadingFromSelection: ((Int) -> Void)?

    final class Coordinator: NSObject, UITextViewDelegate {
        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let wrappingView = textView as? WrappingTextView else {
                return UIMenu(children: suggestedActions)
            }
            guard range.length > 0, wrappingView.onStartReadingFromHere != nil else {
                return UIMenu(children: suggestedActions)
            }
            let action = UIAction(title: "Start Reading From Here") { _ in
                wrappingView.startReadingFromHere(nil)
            }
            return UIMenu(children: [action] + suggestedActions)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = WrappingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context _: Context) {
        if let wrappingView = uiView as? WrappingTextView {
            wrappingView.onStartReadingFromHere = onStartReadingFromSelection
        }
        let needsTextUpdate = uiView.attributedText?.string != text
        if needsTextUpdate {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = lineSpacing
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraph,
            ]
            uiView.attributedText = NSAttributedString(string: text, attributes: attributes)
        }

        if let wrappingView = uiView as? WrappingTextView {
            if needsTextUpdate || wrappingView.lastMeasuredWidth != width {
                wrappingView.lastMeasuredWidth = width
                let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
                let fittingSize = uiView.sizeThatFits(targetSize)
                if height != fittingSize.height {
                    DispatchQueue.main.async {
                        height = fittingSize.height
                    }
                }
            }
        }
    }
}
