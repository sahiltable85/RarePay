import Foundation
import TerminalAPIKit
import AdyenPOS // If this line errors, switch to: import AdyenPOSTEST

@MainActor
final class TapToPayManager: NSObject, ObservableObject {
    @Published var status: String = "Idle"

    // PaymentService needs a non-nil delegate
    lazy var service: PaymentService = {
        PaymentService(delegate: self)
    }()

    // Make sure this is your Mac’s LAN IP (reachable from the iPhone)
    private let sessionsURL = URL(string: "http://192.168.1.204:3000/api/adyen/possdk/sessions")!

    // MARK: - Warmup / linking
    
    /// This function starts the process of linking and warming up the connection.
    /// It should be called from a button tap in your user interface.
    func bootstrap() async {
        do {
            // Always show the Adyen “Link account” UI once
            try await service.linkAccountForTapToPay()

            // Then warm up (this asks Adyen for a setupToken, which triggers the network call)
            try await service.warmUp()
            status = "Ready to take payment"
        } catch {
            status = "Warm-up error: \(error.localizedDescription)"
        }
    }

    // MARK: - Payment
    
    /// This function initiates a payment transaction.
    /// It should only be called after bootstrap() has completed successfully.
    func startPayment(amountMinor: Int, currency: String = "USD") async {
        do {
            // throws accessor (sync)
            let poiId = try service.installationId

            // --- Build Terminal API PaymentRequest ---
            let header = MessageHeader(
                protocolVersion: "3.0",
                messageClass: .service,
                messageCategory: .payment,
                messageType: .request,
                serviceIdentifier: "RarePay",
                saleIdentifier: "RarePay",
                poiIdentifier: poiId
            )

            let saleData = SaleData(
                saleTransactionIdentifier: TransactionIdentifier(
                    transactionIdentifier: UUID().uuidString,
                    date: Date()
                )
            )

            let requested = Decimal(amountMinor) / Decimal(100)
            let txn = PaymentTransaction(
                amounts: Amounts(currency: currency, requestedAmount: requested)
            )

            let payReq = PaymentRequest(saleData: saleData, paymentTransaction: txn)
            let payMsg = Message(header: header, body: payReq)
            let payData = try Coder.encode(payMsg)

            let sdkRequest = try Payment.Request(data: payData)

            let iface = try await service.getPaymentInterface(with: .tapToPay)
            let respData = await service.performTransaction(
                with: sdkRequest,
                paymentInterface: iface,
                presentationMode: .viewModifier
            )

            let decoded: Message<PaymentResponse> =
                try Coder.decode(Message<PaymentResponse>.self, from: respData)
            let result = decoded.body.response.result.rawValue
            status = "Result: \(result)"
        } catch {
            status = "Charge error: \(error.localizedDescription)"
        }
    }
}

// MARK: - PaymentServiceDelegate (setupToken -> sdkData)
extension TapToPayManager: PaymentServiceDelegate {
    func register(with setupToken: String) async throws -> String {
        struct Body: Encodable { let setupToken: String }
        struct SessionsResponse: Decodable { let sdkData: String }

        var req = URLRequest(url: sessionsURL)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Body(setupToken: setupToken))

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        // Accept 2xx (server returns 201 Created)
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "<no body>"
            throw NSError(domain: "SessionsError", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey:
                                      "Sessions \(http.statusCode): \(message)"])
        }
        return try JSONDecoder().decode(SessionsResponse.self, from: data).sdkData
    }
}
