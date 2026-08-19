import SwiftUI
import UIKit

/// The system share sheet, wrapped because it has to carry two different kinds
/// of item at once.
///
/// `ShareLink` takes a homogeneous collection, so it can't send readable text
/// *and* an `.ics` attachment together. `UIActivityViewController` takes
/// `[Any]`, which is what this needs.
///
/// Using the system sheet is also what gets Print and "Save to Files" for free —
/// both appear in the activity list, and Print's preview turns into a PDF if you
/// pinch outward on the page thumbnail.
struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]
    /// Used as the mail subject when the recipient app asks for one.
    let subject: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items,
                                                  applicationActivities: nil)
        controller.setValue(subject, forKey: "subject")
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
