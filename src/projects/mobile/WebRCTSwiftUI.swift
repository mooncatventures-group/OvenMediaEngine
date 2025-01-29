import SwiftUI
import WebRTC
import Starscream

struct WebRTCPlayerView: UIViewRepresentable {
    let videoTrack: RTCVideoTrack?
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let videoView = RTCMTLVideoView(frame: .zero)
        videoView.videoContentMode = .scaleAspectFit
        return videoView
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        if let videoTrack = videoTrack {
            videoTrack.add(uiView)
        }
    }
}

class WebRTCManager: ObservableObject {
    @Published var videoTrack: RTCVideoTrack?
    
    private var peerConnection: RTCPeerConnection?
    private var signalingClient: SignalingClient?
    
    init() {
        setupWebRTC()
    }
    
    private func setupWebRTC() {
        let config = RTCConfiguration()
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["turn:turn.example.com"], username: "username", credential: "password")
        ]
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let factory = RTCPeerConnectionFactory()
        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        
        signalingClient = SignalingClient(url: URL(string: "wss://your-signaling-server.com")!)
        signalingClient?.delegate = self
        
        signalingClient?.connect()
    }
    
    func handleRemoteOffer(_ sdp: RTCSessionDescription) {
        peerConnection?.setRemoteDescription(sdp, completionHandler: { [weak self] error in
            if let error = error {
                print("Error setting remote description: \(error)")
                return
            }
            
            self?.createAnswer()
        })
    }
    
    private func createAnswer() {
        peerConnection?.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), completionHandler: { [weak self] sdp, error in
            if let error = error {
                print("Error creating answer: \(error)")
                return
            }
            
            guard let sdp = sdp else { return }
            self?.peerConnection?.setLocalDescription(sdp, completionHandler: { error in
                if let error = error {
                    print("Error setting local description: \(error)")
                    return
                }
                
                self?.signalingClient?.sendAnswer(sdp)
            })
        })
    }
}

extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let videoTrack = stream.videoTracks.first {
            DispatchQueue.main.async {
                self.videoTrack = videoTrack
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        signalingClient?.sendCandidate(candidate)
    }
    
    // Additional Delegate Methods
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
}

extension WebRTCManager: SignalingClientDelegate {
    func signalingClient(_ client: SignalingClient, didReceiveOffer sdp: RTCSessionDescription) {
        handleRemoteOffer(sdp)
    }
    
    func signalingClient(_ client: SignalingClient, didReceiveCandidate candidate: RTCIceCandidate) {
        peerConnection?.add(candidate)
    }
}

class SignalingClient: WebSocketDelegate {
    private let socket: WebSocket
    weak var delegate: SignalingClientDelegate?
    
    init(url: URL) {
        socket = WebSocket(request: URLRequest(url: url))
        socket.delegate = self
    }
    
    func connect() {
        socket.connect()
    }
    
    func sendAnswer(_ sdp: RTCSessionDescription) {
        let message = [
            "type": "answer",
            "sdp": sdp.sdp
        ]
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            socket.write(data: data)
        }
    }
    
    func sendCandidate(_ candidate: RTCIceCandidate) {
        let message = [
            "type": "candidate",
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": candidate.sdpMLineIndex
        ] as [String: Any]
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            socket.write(data: data)
        }
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let type = json["type"] as? String {
                switch type {
                case "offer":
                    if let sdp = json["sdp"] as? String {
                        let offer = RTCSessionDescription(type: .offer, sdp: sdp)
                        delegate?.signalingClient(self, didReceiveOffer: offer)
                    }
                case "candidate":
                    if let candidate = json["candidate"] as? String,
                       let sdpMid = json["sdpMid"] as? String,
                       let sdpMLineIndex = json["sdpMLineIndex"] as? Int32 {
                        let iceCandidate = RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
                        delegate?.signalingClient(self, didReceiveCandidate: iceCandidate)
                    }
                default:
                    break
                }
            }
        }
    }
    
    func websocketDidConnect(socket: WebSocketClient) {}
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {}
}

protocol SignalingClientDelegate: AnyObject {
    func signalingClient(_ client: SignalingClient, didReceiveOffer sdp: RTCSessionDescription)
    func signalingClient(_ client: SignalingClient, didReceiveCandidate candidate: RTCIceCandidate)
}

struct WebRTCPlayer: View {
    @StateObject private var manager = WebRTCManager()
    
    var body: some View {
        ZStack {
            if let videoTrack = manager.videoTrack {
                WebRTCPlayerView(videoTrack: videoTrack)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Connecting...")
                    .foregroundColor(.gray)
            }
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)
    }
}