// Run with ./verify.command from the Jarvis folder. No key, network or microphone required.
import Foundation
import AVFoundation
@main struct Tests {
    @MainActor static func main() async throws {
        let config = RealtimeProtocol.configuration(memory: "Italiano", vision: false)["session"] as! [String: Any]
        assert((config["tools"] as! [[String: Any]]).first?["name"] as? String == "search_web")
        let audio = config["audio"] as! [String: Any]
        let input = audio["input"] as! [String: Any]
        let vad = input["turn_detection"] as! [String: Any]
        assert(vad["create_response"] as? Bool == true && vad["interrupt_response"] as? Bool == true)
        let withVision = RealtimeProtocol.configuration(memory: "", vision: true)["session"] as! [String: Any]
        assert((withVision["tools"] as! [[String: Any]]).count == 4)
        let noPhoto = RealtimeProtocol.message(text: "Ciao")["item"] as! [String: Any]
        assert((noPhoto["content"] as! [[String: Any]]).count == 1)
        let photo = RealtimeProtocol.message(text: "Guarda", image: Data([1,2,3]))["item"] as! [String: Any]
        assert((photo["content"] as! [[String: Any]])[1]["image_url"] as? String == "data:image/jpeg;base64,AQID")
        // Actual AVAudioConverter: 48kHz mono -> signed 16-bit PCM, 24kHz.
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        buffer.frameLength = 4800
        for i in 0..<4800 { buffer.floatChannelData![0][i] = sin(Float(i) * 2 * .pi * 440 / 48000) * 0.25 }
        let encoder = try PCMEncoder(input: format)
        let encoded = encoder.encode(buffer)!
        assert(encoded.count > 4000 && encoded.count <= 4900 && encoded.count % 2 == 0, "PCM byte count: \(encoded.count)")
        // Initial resampler priming consumes a small prefix; subsequent chunks preserve rate.
        var totalBytes = encoded.count
        for _ in 0..<9 { totalBytes += encoder.encode(buffer)!.count }
        assert(totalBytes > 47000 && totalBytes <= 48100, "One second PCM: \(totalBytes)")
        let energy = encoded.withUnsafeBytes { bytes in bytes.bindMemory(to: Int16.self).contains { abs(Int($0)) > 1000 } }
        assert(energy)
        let live = LiveConversation(); live.testBegin()
        var captures = 0; live.takePhoto = { captures += 1; return Data([1,2,3]) }
        func tool(_ id: String) -> [String: Any] { ["type": "response.done", "response": ["id": "response-" + id, "status": "completed", "output": [["type": "function_call", "name": "look_at_camera", "call_id": id]]]] }
        live.testReceive(tool("denied")); assert(captures == 0)
        live.updateVision(true); live.testReceive(tool("allowed")); assert(captures == 1)
        let eventCount = live.testEvents.count
        live.testReceive(tool("allowed")); assert(captures == 1 && live.testEvents.count == eventCount) // deduplication
        live.testReceive(tool("too-soon")); assert(captures == 1) // no photo loops
        live.toggleMute(); assert(live.muted)
        assert(live.testEvents.last?["type"] as? String == "input_audio_buffer.clear")
        var texts: [String: String] = [:]
        live.onTranscript = { id, _, text in texts[id] = text }
        live.testReceive(["type": "input_audio_buffer.committed", "item_id": "u1"])
        live.testReceive(["type": "conversation.item.input_audio_transcription.completed", "item_id": "u1", "transcript": "Ciao"])
        assert(texts["u1"] == "Ciao")
        live.testReceive(["type": "response.created", "response": ["id": "r1"]])
        live.testReceive(["type": "input_audio_buffer.speech_started"])
        live.testReceive(["type": "response.output_audio_transcript.delta", "response_id": "r1", "item_id": "a1", "delta": "stale"])
        assert(texts["a1"] == nil)
        live.testReceive(["type": "error", "error": ["code": "invalid_api_key"]])
        assert(!live.active && !live.connecting && !live.muted && !live.speaking)
        assert(live.error.contains("chiave"))
        let payload = API.payload(history: (0..<30).map { Message(role: "user", text: "\($0)") }, prompt: "Ciao", photo: nil, memory: "")
        assert((payload["input"] as! [[String: Any]]).count == 21)
        assert(payload["store"] as? Bool == false)
        let text = try API.answer(["output": [["content": [["type":"output_text", "text":"Pronto."]]]]])
        assert(text == "Pronto.")
        do { _ = try API.parse(Data(), status: 401); assertionFailure() } catch { assert(error.localizedDescription.contains("Chiave")) }
        do { _ = try API.parse(Data(), status: 429); assertionFailure() } catch { assert(error.localizedDescription.contains("Credito")) }
        do { _ = try API.answer([:]); assertionFailure() } catch {}
        assert(MemoryCommand.note("Jarvis, ricorda che preferisco risposte brevi") == "preferisco risposte brevi")
        assert(MemoryCommand.note("Cosa ricordi di me?") == nil)
        var savedNote = ""
        let memorizer = LiveConversation(); memorizer.testBegin(); memorizer.rememberNote = { savedNote = $0; return "Salvato" }
        memorizer.testReceive(["type": "response.done", "response": ["id": "mem", "status": "completed", "output": [["type": "function_call", "name": "remember_memory", "call_id": "mem1", "arguments": "{\"note\":\"Risposte brevi\"}"]]]])
        assert(savedNote == "Risposte brevi"); memorizer.stop()
        let cited = try API.answer(["output": [["content": [["type": "output_text", "text": "Prova fonte", "annotations": [["type": "url_citation", "start_index": 6, "end_index": 11, "url": "https://example.com", "title": "Fonte"]]]]]]])
        assert(cited.contains("[Fonte](https://example.com)"))
        let watcher = LiveConversation(); watcher.testBegin()
        watcher.observe(Data([1])); assert(watcher.testEvents.isEmpty)
        watcher.updateVision(true)
        watcher.observe(Data([1])); watcher.observe(Data([2]))
        assert(watcher.testEvents.contains { $0["type"] as? String == "conversation.item.delete" })
        assert(watcher.testEvents.compactMap { ($0["item"] as? [String: Any])?["id"] as? String }.allSatisfy { $0.count <= 32 })
        assert(!watcher.testEvents.contains { $0["type"] as? String == "response.create" })
        var searches = 0
        watcher.searchWeb = { query in searches += 1; assert(query == "Museo Ferrari"); return "Risultato verificato" }
        let webEvent: [String: Any] = ["type": "response.done", "response": ["id": "web", "status": "completed", "output": [["type": "function_call", "name": "search_web", "call_id": "search1", "arguments": "{\"query\":\"Museo Ferrari\"}"]]]]
        watcher.testReceive(webEvent)
        for _ in 0..<10 { await Task.yield() }
        assert(searches == 1)
        watcher.testReceive(webEvent)
        for _ in 0..<10 { await Task.yield() }
        assert(searches == 1)
        assert(watcher.testEvents.contains { ($0["item"] as? [String: Any])?["output"] as? String == "Risultato verificato" })
        var consultations = 0
        watcher.consultExpert = { query in consultations += 1; assert(query == "problema complesso"); return "Soluzione approfondita" }
        let expertEvent: [String: Any] = ["type": "response.done", "response": ["id": "expert", "status": "completed", "output": [["type": "function_call", "name": "consult_expert", "call_id": "expert1", "arguments": "{\"query\":\"problema complesso\"}"]]]]
        watcher.testReceive(expertEvent)
        for _ in 0..<10 { await Task.yield() }
        assert(consultations == 1)
        assert(watcher.testEvents.contains { ($0["item"] as? [String: Any])?["output"] as? String == "Soluzione approfondita" })
        watcher.testReceive(expertEvent)
        for _ in 0..<10 { await Task.yield() }
        assert(consultations == 1)
        assert(RealtimeProtocol.model == "gpt-realtime-2.1-mini")
        watcher.stop()
        print("PASS: web tool, citations, duplicate search, automatic vision and image replacement; PCM conversion; automatic turns; camera opt-in, deduplication and rate limit; mute; transcription; interruption; authentication failure cleanup; bounded history and API errors.")
    }
}
