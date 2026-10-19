import SwiftUI

struct ContentView: View {
    @StateObject private var vpnManager = VPNManager.shared

    var body: some View {
        ZStack {
            Color(hex: "#0D1117").ignoresSafeArea()
            VStack(spacing: 0) {
                Image(systemName: "shield.lefthalf.filled.slash")
                    .font(.system(size: 72))
                    .foregroundColor(Color(hex: "#58A6FF"))
                    .padding(.bottom, 20).padding(.top, 50)

                Text("MyVPN")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(Color(hex: "#E6EDF3"))
                    .padding(.bottom, 4)

                Text("VLESS + XTLS-Reality")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#58A6FF"))
                    .padding(.bottom, 8)

                Text(vpnManager.statusText)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: vpnManager.statusColor))
                    .padding(.bottom, 44)
                    .animation(.easeInOut, value: vpnManager.statusText)

                Button(action: { vpnManager.toggleVPN() }) {
                    Text(vpnManager.isConnected ? "Отключить" : "Подключить")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 220, height: 52)
                        .background(Color(hex: vpnManager.isConnected ? "#DA3633" : "#238636"))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain).padding(.bottom, 14)

                Button(action: { vpnManager.importConfig() }) {
                    Text("Импорт config.json")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#58A6FF"))
                        .frame(width: 220, height: 44)
                        .overlay(Capsule().stroke(Color(hex: "#30363D"), lineWidth: 1))
                }
                .buttonStyle(.plain).padding(.bottom, 28)

                if !vpnManager.publicIP.isEmpty {
                    Text("IP: \(vpnManager.publicIP)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(hex: "#8B949E"))
                        .padding(.bottom, 12)
                }

                ScrollView {
                    Text(vpnManager.logText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "#58A6FF"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(width: 300, height: 90)
                .background(Color(hex: "#161B22"))
                .cornerRadius(8)
                .padding(.bottom, 30)

                Spacer()
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var i: UInt64 = 0; Scanner(string: h).scanHexInt64(&i)
        let a, r, g, b: UInt64
        switch h.count {
        case 6: (a,r,g,b) = (255,i>>16,i>>8&0xFF,i&0xFF)
        case 8: (a,r,g,b) = (i>>24,i>>16&0xFF,i>>8&0xFF,i&0xFF)
        default:(a,r,g,b) = (255,0,0,0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255,
                  blue: Double(b)/255, opacity: Double(a)/255)
    }
}
