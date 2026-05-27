import SwiftUI

struct HelpGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Clear one thing at a time.\nBokeh remembers the rest.")
                        .bokehFont(.body, weight: .medium)
                        .foregroundStyle(Color.theme.bokehBodyColor)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    VStack(spacing: 16) {
                        stepCard(number: 1, icon: "hand.tap", title: "Point & Tap", body: "Point your camera at something you want to clear and tap the screen. Bokeh isolates it from everything else.")
                        stepCard(number: 2, icon: "clock", title: "Put It Away", body: "A timer starts. Take the object to where it belongs, no rush.")
                        stepCard(number: 3, icon: "checkmark.circle", title: "Mark as Done", body: "Tap 'Mark as Done' when you've cleared it. Name it and tag where you put it.")
                        stepCard(number: 4, icon: "magnifyingglass", title: "Find It Later", body: "Search your Focus Log anytime. Ask \"Where are my keys?\" and Bokeh knows.")
                    }

                    Divider()
                        .padding(.vertical, 4)

                    NavigationLink(destination: PrivacyPolicyView()) {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield")
                                .font(.body.weight(.medium))
                            Text("Privacy Policy")
                                .bokehFont(.subheadline, weight: .medium)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(Color.theme.bokehTeal)
                        .padding(16)
                        .background(Color.theme.bokehTealSubtle, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
            }
            .background(Color.theme.bokehSand.ignoresSafeArea())
            .navigationTitle("How to Use Bokeh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.theme.bokehTeal)
                }
            }
        }
    }

    private func stepCard(number: Int, icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.theme.bokehTeal)
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.theme.bokehTeal)
                    Text(title)
                        .bokehFont(.headline, weight: .semibold)
                        .foregroundStyle(Color.theme.bokehTitleColor)
                }
                Text(body)
                    .bokehFont(.subheadline, weight: .regular)
                    .foregroundStyle(Color.theme.bokehBodyColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
    }
}
