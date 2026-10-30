import SwiftUI

@main
struct CentroDeDatosApp: App {
    var body: some Scene {
        WindowGroup {
            WebScreen().ignoresSafeArea()
        }
    }
}

/// Hosts the UIKit controller that owns the web view, so alerts and share sheets have a presenter.
struct WebScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebViewController { WebViewController() }
    func updateUIViewController(_ controller: WebViewController, context: Context) {}
}
