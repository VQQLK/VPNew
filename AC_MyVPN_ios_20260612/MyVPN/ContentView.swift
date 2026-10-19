import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vpnManager = VPNManager.shared
    @State private var showingFilePicker = false

    var body: some View {
        ZStack {
            Color(hex: "#0D1117").ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "shield.lefthalf.filled.slash")
                    .font(.system(size: 80))
                    .foregroundColor(Color(hex: "#58A6FF"))
                    .padding(.bottom, 20)

                Text("MyVPN")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Color(hex: "#E6EDF3"))
                    .padding(.bottom, 4)

                Text("VLESS + XTLS-Reality")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#58A6FF"))
                    .padding(.bottom, 10)

                Text(vpnManager.statusText)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: vpnManager.statusColor))
                    .padding(.bottom, 48)
                    .animation(.easeInOut, value: vpnManager.statusText)

                Button(action: { vpnManager.toggleVPN() }) {
                    Text(vpnManager.isConnected ? "Отключить" : "Подключить")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 220, height: 56)
                        .background(Color(hex: vpnManager.isConnected ? "#DA3633" : "#238636"))
                        .clipShape(Capsule())
                }
                .padding(.bottom, 16)

                Button(action: { showingFilePicker = true }) {
                    Text("Импорт config.json")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#58A6FF"))
                        .frame(width: 220, height: 48)
                        .overlay(Capsule().stroke(Color(hex: "#30363D"), lineWidth: 1))
                }
                .padding(.bottom, 32)

                if !vpnManager.publicIP.isEmpty {
                    Text("IP: \(vpnManager.publicIP)")
                        .font(.system(size: 13, design: .monospaced))
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
                .frame(maxWidth: 320, maxHeight: 90)
                .background(Color(hex: "#161B22"))
                .cornerRadius(8)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        // FIX: убран force-unwrap UTType(filenameExtension:)!
        // Используем UTType.json + кастомный тип с fallback
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: allowedTypes
        ) { result in
            switch result {
            case .success(let url): vpnManager.importConfig(from: url)
            case .failure(let err): vpnManager.appendLog("Ошибка выбора файла: \(err.localizedDescription)")
            }
        }
    }

    // FIX: безопасное построение списка типов без force-unwrap
    private var allowedTypes: [UTType] {
        var types: [UTType] = [.json]
        // Добавляем кастомный тип .json с расширением если система его не знает
        if let custom = UTType(filenameExtension: "json") {
            if !types.contains(custom) { types.append(custom) }
        }
        return types
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
