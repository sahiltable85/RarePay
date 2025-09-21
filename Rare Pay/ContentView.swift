import SwiftUI

struct ContentView: View {
    @StateObject private var ttp = TapToPayManager()
    @State private var amountText = "0.01"

    var body: some View {
        VStack(spacing: 16) {
            Text("Tap to Pay (TEST)").font(.title3)
            Text(ttp.status).font(.footnote).foregroundStyle(.secondary)
            
            Button("Connect and Warm Up") {
                Task {
                    await ttp.bootstrap()
                }
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 12) {
                TextField("Amount (USD)", text: $amountText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                Button("Charge") {
                    let cleaned = amountText.replacingOccurrences(of: ",", with: ".")
                    let cents = Int(round((Double(cleaned) ?? 0) * 100))
                    Task { await ttp.startPayment(amountMinor: max(cents, 1)) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
  
        // This presents the Apple Tap to Pay sheet
        .transactionModal(with: ttp.service)
    }
}
