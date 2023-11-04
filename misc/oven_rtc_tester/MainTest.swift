//
//  MainTest.swift
//  WebRCTDemo
//
//
import Foundation
import AVFoundation
import WebRTC
import Starscream

let delayWarningThreshold = 1000
let lossWarningThreshold = 5
let delayReportPeriod = 5000

func main() {
    let requestURL = CommandLine.arguments[1]
    let numberOfClient = Int(CommandLine.arguments[2]) ?? 1
    let connectionInterval = Int(CommandLine.arguments[3]) ?? 100
    let summaryInterval = Int(CommandLine.arguments[4]) ?? 5000
    let lifetime = Int(CommandLine.arguments[5]) ?? 0
    
    guard let url = URL(string: requestURL) else {
        print("-url parameter is required and must be valid. (input : \(requestURL))")
        return
    }
    
    var clients = [OMEClient]()
    let clientGroup = DispatchGroup()
    let clientQueue = DispatchQueue(label: "clientQueue")
    
    for i in 0..<numberOfClient {
        clientGroup.enter()
        clientQueue.asyncAfter(deadline: .now() + .milliseconds(connectionInterval * i)) {
            let client = OMEClient(name: "client_\(i)")
            client.run(url: url)
            clients.append(client)
            print("\(client.name) has started")
            clientGroup.leave()
        }
    }
    
    let summaryTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
    summaryTimer.schedule(deadline: .now(), repeating: .milliseconds(summaryInterval))
    summaryTimer.setEventHandler {
        reportSummary(clients: clients)
    }
    summaryTimer.resume()
    
    let lifetimeTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
    lifetimeTimer.schedule(deadline: .now() + .seconds(lifetime))
    lifetimeTimer.setEventHandler {
        print("Test ended (lifetime: \(lifetime) seconds)")
        clientQueue.sync {
            clients.forEach { $0.stop() }
        }
        summaryTimer.cancel()
    }
    lifetimeTimer.resume()
    
    signal(SIGINT) { _ in
        print("Test stopped by user")
        clientQueue.sync {
            clients.forEach { $0.stop() }
        }
        summaryTimer.cancel()
    }
    
    clientGroup.wait()
    
    print("***************************")
    print("Reports")
    print("***************************")
    reportSummary(clients: clients)
    print("<Details>")
    clients.forEach { $0.report() }
}

func reportSummary(clients: [OMEClient]) {
    print("<Summary>")
    let clientCount = clients.count
    guard clientCount > 0 else { return }
    
    let firstSessionStartTime = clients[0].stat.startTime
    print("Running time: \(Date().timeIntervalSince(firstSessionStartTime).rounded()) seconds")
    print("Number of clients: \(clientCount)")
    
    var connectionStateCount = (
        ICEConnectionStateNew: 0,
        ICEConnectionStateChecking: 0,
        ICEConnectionStateConnected: 0,
        ICEConnectionStateCompleted: 0,
        ICEConnectionStateDisconnected: 0,
        ICEConnectionStateFailed: 0,
        ICEConnectionStateClosed: 0
    )
    
    var totalStat = SessionStat()
    var minVideoDelay = Double.greatestFiniteMagnitude
    var maxVideoDelay = 0.0
    var minAudioDelay = Double.greatestFiniteMagnitude
    var maxAudioDelay = 0.0
    var minAvgFPS = Double.greatestFiniteMagnitude
    var maxAvgFPS = 0.0
    var minAvgBPS = Int64.max
    var maxAvgBPS = Int64.min
    var minGOP = Double.greatestFiniteMagnitude
    var maxGOP = 0.0
    
    for client in clients {
        let stat = client.stat
        switch stat.connectionState {
        case .new:
            connectionStateCount.ICEConnectionStateNew += 1
        case .checking:
            connectionStateCount.ICEConnectionStateChecking += 1
        case .connected:
            connectionStateCount.ICEConnectionStateConnected += 1
        case .completed:
            connectionStateCount.ICEConnectionStateCompleted += 1
        case .disconnected:
            connectionStateCount.ICEConnectionStateDisconnected += 1
        case .failed:
            connectionStateCount.ICEConnectionStateFailed += 1
        case .closed:
            connectionStateCount.ICEConnectionStateClosed += 1
        @unknown default:
            break
        }
        
        if stat.connectionState != .connected {
            continue
        }
        
        let gop = Double(stat.totalVideoFrames) / Double(stat.totalVideoKeyframes)
        
        if totalStat.startTime == nil {
            totalStat = stat
            maxAvgFPS = totalStat.avgFPS
            minAvgFPS = totalStat.avgFPS
            maxAvgBPS = totalStat.avgBPS
            minAvgBPS = totalStat.avgBPS
            minVideoDelay = totalStat.videoDelay
            maxVideoDelay = totalStat.videoDelay
            minAudioDelay = totalStat.audioDelay
            maxAudioDelay = totalStat.audioDelay
            minGOP = gop
            maxGOP = gop
            continue
        }
        
        minAvgFPS = min(minAvgFPS, stat.avgFPS)
        maxAvgFPS = max(maxAvgFPS, stat.avgFPS)
        minAvgBPS = min(minAvgBPS, stat.avgBPS)
        maxAvgBPS = max(maxAvgBPS, stat.avgBPS)
        minVideoDelay = min(minVideoDelay, stat.videoDelay)
        maxVideoDelay = max(maxVideoDelay, stat.videoDelay)
        minAudioDelay = min(minAudioDelay, stat.audioDelay)
        maxAudioDelay = max(maxAudioDelay, stat.audioDelay)
        minGOP = min(minGOP, gop)
        maxGOP = max(maxGOP, gop)
        
        totalStat.avgBPS += stat.avgBPS
        totalStat.avgFPS += stat.avgFPS
        totalStat.totalBytes += stat.totalBytes
        totalStat.totalVideoFrames += stat.totalVideoFrames
        totalStat.totalVideoKeyframes += stat.totalVideoKeyframes
        totalStat.totalRtpPackets += stat.totalRtpPackets
        totalStat.packetLoss += stat.packetLoss
    }
    
    print("ICE Connection State: New(\(connectionStateCount.ICEConnectionStateNew)), Checking(\(connectionStateCount.ICEConnectionStateChecking)), Connected(\(connectionStateCount.ICEConnectionStateConnected)), Completed(\(connectionStateCount.ICEConnectionStateCompleted)), Disconnected(\(connectionStateCount.ICEConnectionStateDisconnected)), Failed(\(connectionStateCount.ICEConnectionStateFailed)), Closed(\(connectionStateCount.ICEConnectionStateClosed))")
    
    let connected = connectionStateCount.ICEConnectionStateConnected
    guard connected > 0 else { return }
    
    print("Avg Video Delay(\(totalStat.videoDelay / Double(connected))) ms, Max Video Delay(\(maxVideoDelay)) ms, Min Video Delay(\(minVideoDelay)) ms")
    print("Avg Audio Delay(\(totalStat.audioDelay / Double(connected))) ms, Max Audio Delay(\(maxAudioDelay)) ms, Min Audio Delay(\(minAudioDelay)) ms")
    print("Avg GOP(\(Double(totalStat.totalVideoFrames) / Double(totalStat.totalVideoKeyframes))), Max GOP(\(maxGOP)), Min GOP(\(minGOP))")
    print("Avg FPS(\(totalStat.avgFPS / Double(connected))), Max FPS(\(maxAvgFPS)), Min FPS(\(minAvgFPS))")
    print("Avg BPS(\(totalStat.avgBPS / Int64(connected))) bps, Max BPS(\(maxAvgBPS)) bps, Min BPS(\(minAvgBPS)) bps")
    print("Total Bytes(\(totalStat.totalBytes)) Bytes, Avg Bytes(\(totalStat.totalBytes / Int64(connected))) Bytes")
    print("Total Packets(\(totalStat.totalRtpPackets)), Avg Packets(\(totalStat.totalRtpPackets / Int64(connected)))")
    print("Total Packet Losses(\(totalStat.packetLoss)), Avg Packet Losses(\(totalStat.packetLoss / Int64(connected)))")
    print()
}

class SignalingClient {
    let url: URL
    var socket: WebSocket?
    
    init(url: URL) {
        self.url = url
    }
    
    func connect() throws {
        let urlRequest = URLRequest(url:url)
        socket = WebSocket(request: urlRequest)
        try socket?.connect()
    }
    
    func close() {
        socket?.disconnect()
    }
    
    func getOffer() throws -> SignalMessage {
        guard let socket = socket else {
            throw SignalingError.notConnected
        }
        
        try socket.write(message: SignalMessage(command: "request_offer").marshal())
        
        guard let offerMsg = try socket.read() else {
            throw SignalingError.offerMessageNotFound
        }
        
        let offer = try JSONDecoder().decode(SignalMessage.self, from: offerMsg)
        
        guard offer.sdp.type != 0 else {
            throw SignalingError.invalidOfferMessage
        }
        
        return offer
    }
    
    func sendAnswer(answer: SignalMessage) throws {
        guard let socket = socket else {
            throw SignalingError.notConnected
        }
        
        let byteAnswer = try JSONEncoder().encode(answer)
        try socket.write(message: byteAnswer)
    }
    
    func readPump() throws {
        guard let socket = socket else {
            throw SignalingError.notConnected
        }
        
        while true {
            guard let _ = try socket.read() else {
                break
            }
        }
    }
}

struct ICEServer: Codable {
    let urls: [String]
    let userName: String?
    let credential: String?
}

struct SignalMessage: Codable {
    let command: String
    let id: Int64?
    let peerId: Int64?
    let sdp: RTCSessionDescription?
    let candidates: [RTCICECandidateInit]?
    let iceServers: [ICEServer]?
    
    enum CodingKeys: String, CodingKey {
        case command, id, peerId, sdp, candidates
        case iceServers = "ice_servers"
    }
    
    func marshal() throws -> Data {
        return try JSONEncoder().encode(self)
    }
    
    static func unmarshal(data: Data) throws -> SignalMessage {
        return try JSONDecoder().decode(SignalMessage.self, from: data)
    }
}

enum SignalingError: Error {
    case notConnected
    case offerMessageNotFound
    case invalidOfferMessage
}

class OMEClient {
    let name: String
    let sc: SignalingClient
    let peerConnection: RTCPeerConnection
    var videoAvailable = false
    var videoMimeType = ""
    var audioAvailable = false
    var audioMimeType = ""
    var stat = SessionStat()
    let once = Once()
    
    init(name: String) {
        self.name = name
        self.sc = SignalingClient(url: URL(string: "")!)
        self.peerConnection = RTCPeerConnection()
    }
    
    func run(url: URL) {
        do {
            try sc.connect()
            let offer = try sc.getOffer()
            
            var config = RTCConfiguration()
            config.iceServers = [
                RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
                RTCIceServer(urlStrings: ["turn:turn.example.com"], username: "username", credential: "password")
            ]
            
            if let iceServers = offer.iceServers {
                config.iceServers += iceServers.map { RTCIceServer(urlStrings: $0.urls, username: $0.userName, credential: $0.credential) }
            }
            
            if let iceServers = offer.iceServers {
                config.iceTransportPolicy = .relay
            }
            
            let mediaEngine = RTCMediaEngine()
            try mediaEngine.registerCodec(RTCRtpCodecParameters(mimeType: "video/H264", clockRate: 90000, channels: 0, sdpFmtpLine: "", rtcpFeedback: nil), type: .video)
            try mediaEngine.registerCodec(RTCRtpCodecParameters(mimeType: "video/VP8", clockRate: 90000, channels: 0, sdpFmtpLine: "", rtcpFeedback: nil), type: .video)
            try mediaEngine.registerCodec(RTCRtpCodecParameters(mimeType: "audio/opus", clockRate: 48000, channels: 0, sdpFmtpLine: "", rtcpFeedback: nil), type: .audio)
            
            let setting = RTCPeerConnectionFactoryOptions()
            setting.disableEncryption = true
            let factory = RTCPeerConnectionFactory(options: setting)
            let api = RTCPeerConnection(with: factory, configuration: config)
            
            peerConnection = api
            
            peerConnection.delegate = self
            
            try peerConnection.setRemoteDescription(offer.sdp)
            
            if let candidates = offer.candidates {
                candidates.forEach { peerConnection.add($0) }
            }
            
            let answerSdp = try peerConnection.createAnswer()
            try sc.sendAnswer(answer: SignalMessage(command: "answer", id: offer.id, peerId: 0, sdp: answerSdp, candidates: nil, iceServers: nil))
            try peerConnection.setLocalDescription(answerSdp)
            
            try sc.readPump()
        } catch {
            print(error)
        }
    }
    
    func stop() {
        sc.close()
    }
    
    func report() {
        let stat = self.stat
        
        var videoDelay = 0.0
        var audioDelay = 0.0
        
        if let videoRtpTimestampElapsedMSec = stat.videoRtpTimestampElapsedMSec {
            videoDelay = abs(Double(Date().timeIntervalSince(stat.startTime) * 1000) - Double(videoRtpTimestampElapsedMSec))
        }
        
        if let audioRtpTimestampElapsedMSec = stat.audioRtpTimestampElapsedMSec {
            audioDelay = abs(Double(Date().timeIntervalSince(stat.startTime) * 1000) - Double(audioRtpTimestampElapsedMSec))
        }
        
        print("\u{001B}[32m[\(name)]\u{001B}[0m")
        print("\trunning_time(\(Date().timeIntervalSince(stat.startTime).rounded())) connection_state(\(stat.connectionState.rawValue)) total_packets(\(stat.totalRtpPackets)) packet_loss(\(stat.packetLoss))")
        print("\tlast_video_delay (\(videoDelay) ms) last_audio_delay (\(audioDelay) ms)")
        print("\ttotal_bytes(\(stat.totalBytes) bytes) avg_bps(\(stat.avgBPS) bps) min_bps(\(stat.minBPS) bps) max_bps(\(stat.maxBPS) bps)")
        print("\ttotal_video_frames(\(stat.totalVideoFrames)) total_video_keyframes(\(stat.totalVideoKeyframes)) avg_gop(\(Double(stat.totalVideoFrames) / Double(stat.totalVideoKeyframes))) avg_fps(\(stat.avgFPS)) min_fps(\(stat.minFPS)) max_fps(\(stat.maxFPS))")
        print()
    }
}

extension OMEClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("\(name) signaling state has changed \(stateChanged.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("\(name) stream has started, of type \(stream.videoTracks.first?.mediaType.rawValue ?? "")")
        
        stat.startTime = Date()
        
        if let videoTrack = stream.videoTracks.first {
            videoAvailable = true
            videoMimeType = videoTrack.codec.mimeType
        }
        
        if let audioTrack = stream.audioTracks.first {
            audioAvailable = true
            audioMimeType = audioTrack.codec.mimeType
        }
        
        DispatchQueue.global().async {
            var lastTime = Date()
            var lastFrames = Int64(0)
            var lastBytes = Int64(0)
            
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                let stat = self.stat
                let currVideoFrames = stat.totalVideoFrames
                let currTotalBytes = stat.totalBytes
                let fps = Double(currVideoFrames - lastFrames) / Date().timeIntervalSince(lastTime)
                let bps = Int64(Double(currTotalBytes - lastBytes) / Date().timeIntervalSince(lastTime) * 8)
                
                if self.stat.maxFPS == 0 || self.stat.maxFPS < fps {
                    self.stat.maxFPS = fps
                }
                
                if self.stat.minFPS == 0 || self.stat.minFPS > fps {
                    self.stat.minFPS = fps
                }
                
                if self.stat.maxBPS == 0 || self.stat.maxBPS < bps {
                    self.stat.maxBPS = bps
                }
                
                if self.stat.minBPS == 0 || self.stat.minBPS > bps {
                    self.stat.minBPS = bps
                }
                
                self.stat.avgBPS = Int64(Double(stat.totalBytes) / Date().timeIntervalSince(stat.startTime) * 8)
                self.stat.avgFPS = Double(stat.totalVideoFrames) / Date().timeIntervalSince(stat.startTime)
                
                lastTime = Date()
                lastFrames = currVideoFrames
                lastBytes = currTotalBytes
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCICECandidate) {
        print("\(name) candidate found")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCICEConnectionState) {
        print("\(name) connection state has changed \(newState.rawValue)")
        stat.connectionState = newState
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCICEGatheringState) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCICECandidate]) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove dataChannel: RTCDataChannel) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove dataChannel: RTCDataChannel) {}
}

struct SessionStat {
    var startTime: Date?
    var connectionState: RTCICEConnectionState = .new
    var maxFPS = 0.0
    var avgFPS = 0.0
    var minFPS = 0.0
    var maxBPS: Int64 = 0
    var avgBPS: Int64 = 0
    var minBPS: Int64 = 0
    var totalBytes: Int64 = 0
    var totalVideoFrames: Int64 = 0
    var totalVideoKeyframes: Int64 = 0
    var totalRtpPackets: Int64 = 0
    var packetLoss: Int64 = 0
    var videoRtpTimestampElapsedMSec: Int64?
    var videoDelay = 0.0
    var audioRtpTimestampElapsedMSec: Int64?
    var audioDelay = 0.0
}
