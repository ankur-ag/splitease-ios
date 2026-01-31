//
//  StoreManager.swift
//  splitease
//
//  Created by SplitEase on 1/31/26.
//

import Foundation
import StoreKit

class StoreManager {
    static let shared = StoreManager()
    
    var transactionListener: Task<Void, Error>?
    
    private init() {
        // Initialization handled via startListener() to ensure it's called at launch
    }
    
    func startListener() {
        guard transactionListener == nil else { return }
        
        print("🛒 StoreManager: Starting transaction listener...")
        
        // Check for existing entitlements first
        Task {
            await self.updateCustomerProductStatus()
        }
        
        transactionListener = Task.detached {
            // Iterate through any transactions that finish outside the app.
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    
                    // Deliver content to the user.
                    await self.updateCustomerProductStatus()
                    
                    // Always finish a transaction.
                    await transaction.finish()
                    
                    print("✅ StoreManager: Handled transaction: \(transaction.productID)")
                } catch {
                    // StoreKit has a transaction that fails verification. Don't deliver content to the user.
                    print("❌ StoreManager: Transaction failed verification: \(error)")
                }
            }
        }
    }
    
    func checkVerified<T>(_ result: VerificationResult<T>) async throws -> T {
        // Check whether the JWS token is deserialized and verified by the App Store.
        switch result {
        case .unverified(_, let error):
            // StoreKit parses the JWS, but it fails verification.
            throw error
        case .verified(let safe):
            // The JWS is verified.
            return safe
        }
    }
    
    @MainActor
    func updateCustomerProductStatus() async {
        // Check for active products and update app state.
        // For SplitEase, we set "hasDonated" if they have any verified tip purchase.
        
        var hasActiveDonation = false
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try await self.checkVerified(result)
                if transaction.productID.starts(with: "tip.") {
                    hasActiveDonation = true
                    print("✅ StoreManager: Verified active entitlement: \(transaction.productID)")
                }
            } catch {
                print("❌ StoreManager: Entitlement verification failed")
            }
        }
        
        if hasActiveDonation {
            UserDefaults.standard.set(true, forKey: "hasDonated")
        }
    }
}
