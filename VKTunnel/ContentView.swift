import SwiftUI
import NetworkExtension

struct ContentView: View {
    @State private var isConnected = false
    @State private var statusText = "Отключено"
    
    var body: some View {
        VStack(spacing: 25) {
            Text("VK Tunnel")
                .font(.largeTitle)
                .bold()
            
            Text(statusText)
                .font(.title3)
                .foregroundColor(isConnected ? .green : .gray)
            
            Button(action: toggleVPN) {
                Text(isConnected ? "Остановить" : "Запустить")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 220, height: 55)
                    .background(isConnected ? Color.red : Color.blue)
                    .cornerRadius(14)
            }
        }
        .padding()
        .onAppear(perform: checkVPNStatus)
    }

    /// Включение или отключение системного профиля VPN
    private func toggleVPN() {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            let manager = managers?.first ?? NETunnelProviderManager()
            
            // Первичная регистрация конфигурации туннеля в iOS
            if manager.protocolConfiguration == nil {
                let providerProtocol = NETunnelProviderProtocol()
                providerProtocol.providerBundleIdentifier = "com.vktunnel.app.packettunnel"
                providerProtocol.serverAddress = "192.0.2.1"
                
                manager.protocolConfiguration = providerProtocol
                manager.localizedDescription = "VK Tunnel"
                manager.isEnabled = true
            }
            
            manager.saveToPreferences { saveError in
                guard saveError == nil else { return }
                
                manager.loadFromPreferences { _ in
                    if self.isConnected {
                        manager.connection.stopVPNTunnel()
                        self.isConnected = false
                        self.statusText = "Отключено"
                    } else {
                        do {
                            try manager.connection.startVPNTunnel()
                            self.isConnected = true
                            self.statusText = "Подключено"
                        } catch {
                            self.statusText = "Ошибка запуска"
                        }
                    }
                }
            }
        }
    }

    /// Проверка текущего статуса VPN при открытии приложения
    private func checkVPNStatus() {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            if let manager = managers?.first {
                self.isConnected = (manager.connection.status == .connected)
                self.statusText = self.isConnected ? "Подключено" : "Отключено"
            }
        }
    }
}
