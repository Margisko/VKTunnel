import NetworkExtension
import Network

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.vktunnel.provider")
    
    // Настройки VPS сервера
    private let vpsHost: Network.NWEndpoint.Host = "192.0.2.1"
    private let vpsPort: Network.NWEndpoint.Port = 51820
    private let channelId: UInt16 = 0x4000

    override func startTunnel(options: [String : NSObject]? = nil, completionHandler: @escaping (Error?) -> Void) {
        // Конфигурация виртуального сетевого интерфейса iOS
        let tunnelSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "192.0.2.1")
        
        // Маршрутизация всего IPv4 трафика устройства
        let ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        tunnelSettings.ipv4Settings = ipv4Settings
        
        // Перехват DNS-запросов
        let dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dnsSettings.matchDomains = [""]
        tunnelSettings.dnsSettings = dnsSettings

        // Применение настроек в ядре iOS
        setTunnelNetworkSettings(tunnelSettings) { [weak self] error in
            if let error = error {
                completionHandler(error)
                return
            }
            self?.connectToVPS()
            self?.readSystemPackets()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        connection?.cancel()
        completionHandler()
    }

    private func connectToVPS() {
        let parameters = NWParameters.udp
        connection = NWConnection(host: vpsHost, port: vpsPort, using: parameters)
        connection?.start(queue: queue)
        receiveFromVPS()
    }

    /// Перехват сетевых пакетов из системы и упаковка в STUN
    private func readSystemPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }
            for packet in packets {
                let stunPacket = self.wrapStunChannelData(payload: packet)
                self.connection?.send(content: stunPacket, completion: .contentProcessed({ _ in }))
            }
            self.readSystemPackets()
        }
    }

    /// Прием данных от VPS и запись обратно в систему
    private func receiveFromVPS() {
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 65535) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, let rawPayload = self.unwrapStunChannelData(data: data) {
                self.packetFlow.writePackets([rawPayload], withProtocols: [AF_INET as NSNumber])
            }
            if !isComplete && error == nil {
                self.receiveFromVPS()
            }
        }
    }

    /// Упаковка IP-пакета в кадр STUN ChannelData (RFC 5766)
    private func wrapStunChannelData(payload: Data) -> Data {
        var packet = Data()
        var chId = channelId.bigEndian
        var length = UInt16(payload.count).bigEndian
        
        packet.append(Data(bytes: &chId, count: 2))
        packet.append(Data(bytes: &length, count: 2))
        packet.append(payload)
        
        let paddingLen = (4 - (payload.count % 4)) % 4
        if paddingLen > 0 {
            packet.append(Data(repeating: 0, count: paddingLen))
        }
        return packet
    }

    /// Распаковка кадра STUN ChannelData
    private func unwrapStunChannelData(data: Data) -> Data? {
        guard data.count >= 4 else { return nil }
        let lengthBytes = data.subdata(in: 2..<4)
        let length = Int(UInt16(bigEndian: lengthBytes.withUnsafeBytes { $0.load(as: UInt16.self) }))
        
        guard data.count >= 4 + length else { return nil }
        return data.subdata(in: 4..<(4 + length))
    }
}
