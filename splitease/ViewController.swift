//
//  ViewController.swift
//  SplitEaseWebView
//
//  Complete working example for iOS WebView with Tip Jar
//  IMPORTANT: Make sure this is your actual ViewController.swift file
//

import UIKit
@preconcurrency import WebKit
import StoreKit

class ViewController: UIViewController {
    var webView: WKWebView!
    var loadingIndicator: UIActivityIndicatorView!
    var dimmingView: UIView? // Custom dimming view for overlays
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupWebView()
        setupLoadingIndicator()
        loadApp()
    }
    
    func setupWebView() {
        // Create webview configuration
        let webConfiguration = WKWebViewConfiguration()
        
        // JavaScript is enabled by default in WKWebView (iOS 14+)
        // No need to set javaScriptEnabled - it's deprecated
        
        // Allow inline media playback
        webConfiguration.allowsInlineMediaPlayback = true
        
        // CRITICAL: Set up JavaScript bridge BEFORE creating webview
        let userContentController = WKUserContentController()
        // Register the tip jar message handler
        userContentController.add(self, name: "tipJar")
        // Register the app store rating handler
        userContentController.add(self, name: "appStoreRating")
        
        // Inject a flag to let the web app know it's running in native iOS
        // This is more reliable than checking for message handlers or user agent
        let source = "window.isNativeApp = true;"
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        userContentController.addUserScript(script)
        
        // Inject app version so web app can display it
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let versionSource = "window.appVersion = \"\(appVersion)\";"
        let versionScript = WKUserScript(source: versionSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        userContentController.addUserScript(versionScript)
        
        webConfiguration.userContentController = userContentController
        
        print("🔧 Bridge setup: tipJar handler registered")
        
        // Create webview with configuration
        webView = WKWebView(frame: view.bounds, configuration: webConfiguration)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Enable Safari Web Inspector for debugging
        #if DEBUG
        webView.isInspectable = true
        #endif
        
        // Add to view
        view.addSubview(webView)
        
        print("✅ WebView created with bridge configuration")
    }
    
    func setupLoadingIndicator() {
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.center = view.center
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
    }
    
    func loadApp() {
        // Read URL from Info.plist (configured via xcconfig files)
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "BackendURL") as? String,
              let url = URL(string: urlString) else {
            showError("Invalid or missing Backend URL configuration")
            return
        }
        
        // If we have a saved deep link URL that hasn't been handled yet, use that instead
        if let pendingUrl = UserDefaults.standard.url(forKey: "pendingDeepLinkUrl") {
            UserDefaults.standard.removeObject(forKey: "pendingDeepLinkUrl")
            print("🔗 Using pending deep link URL: \(pendingUrl)")
            loadUrl(pendingUrl)
            return
        }
        
        loadUrl(url)
    }
    
    func loadUrl(_ url: URL) {
        let request = URLRequest(url: url)
        webView.load(request)
        loadingIndicator.startAnimating()
        print("🌐 Loading URL: \(url.absoluteString)")
    }

    // MARK: - UI Helpers
    func addDimmingView() {
        let dimView = UIView(frame: view.bounds)
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        dimView.alpha = 0
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(dimView)
        dimmingView = dimView
        
        UIView.animate(withDuration: 0.2) {
            dimView.alpha = 1
        }
    }

    func removeDimmingView() {
        guard let dimView = dimmingView else { return }
        
        UIView.animate(withDuration: 0.2, animations: {
            dimView.alpha = 0
        }) { _ in
            dimView.removeFromSuperview()
            self.dimmingView = nil
        }
    }
}

// MARK: - WKNavigationDelegate
extension ViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingIndicator.startAnimating()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
        print("✅ Page loaded successfully")
        
        // Verify bridge is accessible from JavaScript
        webView.evaluateJavaScript("""
            console.log('Bridge check:', {
                hasWebkit: typeof window.webkit !== 'undefined',
                hasMessageHandlers: typeof window.webkit?.messageHandlers !== 'undefined',
                hasTipJar: typeof window.webkit?.messageHandlers?.tipJar !== 'undefined'
            });
        """) { result, error in
            if let error = error {
                print("❌ JavaScript evaluation error: \(error)")
            } else {
                print("✅ Bridge verification script executed")
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
        
        let errorMessage = """
        Failed to load app:
        
        \(error.localizedDescription)
        
        Make sure:
        1. Next.js server is running (npm run dev)
        2. Mac and iPhone are on same WiFi
        3. URL is correct
        4. Firewall allows port 3000
        """
        
        Task { @MainActor in
            self.showError(errorMessage)
        }
        print("❌ WebView Error: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Log all navigation for debugging
        if let url = navigationAction.request.url {
            print("🔗 Loading: \(url.absoluteString)")
        }
        decisionHandler(.allow)
    }
}

// MARK: - WKScriptMessageHandler (iOS Bridge)
extension ViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("📱 Received message: \(message.name)")
        if message.name == "tipJar" {
            print("💰 Tip jar requested from web app")
            showTipJar()
        } else if message.name == "appStoreRating" {
            print("⭐ App store rating requested")
            requestAppStoreReview()
        } else {
            print("⚠️ Unknown message handler: \(message.name)")
        }
    }
    
    @MainActor
    func requestAppStoreReview() {
        print("⭐ Requesting App Store Review")
        if let windowScene = view.window?.windowScene {
            SKStoreReviewController.requestReview(in: windowScene)
        } else {
            print("❌ Could not find window scene for review")
        }
    }
    
    func showTipJar() {
        print("💰 showTipJar() called")
        
        // Check if user has already donated
        let hasDonated = UserDefaults.standard.bool(forKey: "hasDonated")
        if hasDonated {
            print("✅ User has already donated, skipping tip jar")
            return
        }
        
        // Check if StoreKit 2 is available (iOS 15+)
        if #available(iOS 15.0, *) {
            print("✅ StoreKit 2 available, loading products...")
            // Use StoreKit 2 Tip Jar
            Task {
                do {
                    // Get available tip products
                    let productIds = [
                        "tip.medium",   // $2.99 - Donut
                        "tip.large",    // $4.99 - Coffee
                        "tip.small"     // $0.99 - Lunch (reordered)
                    ]
                    print("📦 Requesting products: \(productIds)")
                    let products = try await Product.products(for: productIds)
                    print("✅ Loaded \(products.count) products")
                    
                    // Show tip options
                    await MainActor.run {
                        if products.isEmpty {
                            print("⚠️ No products available, showing thank you message")
                            showThankYouMessage()
                        } else {
                            showTipOptions(products: products)
                        }
                    }
                } catch {
                    print("❌ Error loading tip products: \(error)")
                    print("❌ Error details: \(error.localizedDescription)")
                    // Show error message to user
                    await MainActor.run {
                        showError("Unable to load tip options. Please check StoreKit configuration.")
                    }
                }
            }
        } else {
            // iOS 14 and below - show thank you message
            print("⚠️ iOS 14 or below, showing thank you message")
            showThankYouMessage()
        }
    }
    
    @MainActor
    func showTipOptions(products: [Product]) {
        print("💝 Showing tip options with \(products.count) products")
        
        // Add dimming view for better focus
        addDimmingView()
        
        // Sort products by price (low to high)
        let sortedProducts = products.sorted { product1, product2 in
            return product1.price < product2.price
        }
        
        let alert = UIAlertController(
            title: "💝 Love the App?",
            message: "If we made splitting expenses easier, consider leaving a tip!",
            preferredStyle: .actionSheet
        )
        
        // Add tip options with creative, engaging labels
        for product in sortedProducts {
            let price = product.displayPrice
            
            // Create fun, engaging labels based on tip amount
            // small = donut, medium = coffee, large = lunch
            let tipLabel: String
            switch product.id {
            case "tip.small":
                tipLabel = "Buy me a coffee"
            case "tip.medium":
                tipLabel = "Keep this app ad free"
            case "tip.large":
                tipLabel = "Support feature upgrades"
            default:
                tipLabel = product.displayName.isEmpty ? "💝 Show some love" : product.displayName
            }
            
            let title = "\(tipLabel) - \(price)"
            print("📝 Adding tip option: \(title) for product \(product.id)")
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.removeDimmingView()
                Task {
                    await self?.purchaseTip(product: product)
                }
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.removeDimmingView()
        })
        
        // For iPad
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        // Ensure we're on the main thread and view is loaded
        if isViewLoaded {
            present(alert, animated: true) {
                print("✅ Tip jar alert presented")
            }
        } else {
            print("⚠️ View not loaded yet, scheduling tip jar for later")
            DispatchQueue.main.async {
                self.present(alert, animated: true) {
                    print("✅ Tip jar alert presented (delayed)")
                }
            }
        }
    }
    
    @MainActor
    func purchaseTip(product: Product) async {
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // Transaction verified
                    await transaction.finish()
                    
                    // Mark that user has donated
                    UserDefaults.standard.set(true, forKey: "hasDonated")
                    print("✅ Donation recorded, will not ask again")
                    
                    showThankYouMessage()
                case .unverified(_, let error):
                    print("Transaction unverified: \(error)")
                    showError("Payment verification failed. Please try again.")
                }
            case .userCancelled:
                // User cancelled, do nothing
                break
            case .pending:
                showMessage("Payment is pending. Thank you!")
            @unknown default:
                break
            }
        } catch {
            print("Purchase error: \(error)")
            showError("Failed to process tip. Please try again.")
        }
    }
    
    @MainActor
    func showThankYouMessage() {
        let alert = UIAlertController(
            title: "Thank You! 🙏",
            message: "Your support means the world to us!",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "You're Welcome!", style: .default))
        present(alert, animated: true)
    }
    
    @MainActor
    func showError(_ message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    @MainActor
    func showMessage(_ message: String) {
        let alert = UIAlertController(
            title: "Thank You",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

