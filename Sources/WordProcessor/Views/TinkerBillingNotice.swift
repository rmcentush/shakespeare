import SwiftUI

struct TinkerBillingNotice: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Tinker billing needs attention")
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Open Tinker Billing ↗", destination: InferenceSettings.tinkerBillingURL)
                    .font(.caption.weight(.medium))
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
    }
}
