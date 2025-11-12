//
//  MIDIInstrumentPlayer.swift
//  MIDIInstrumentPlayer
//
//  Created by Rahul Dhodapkar on 7/12/25.
//  Copyright © 2025 Rahul Dhodapkar. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

struct MIDIPreset {
    let name: String
    let program: UInt8
    let url: URL

    static func defaultSoundbankURL() -> URL {
        return Bundle.main.url(forResource: "GeneralUser GS MuseScore v1.442", withExtension: "sf2")!
    }

    static var acousticGrandPiano: MIDIPreset {
        MIDIPreset(name: "Piano", program: 0, url: defaultSoundbankURL())
    }

    static var strings: MIDIPreset {
        MIDIPreset(name: "Strings", program: 48, url: defaultSoundbankURL())
    }
}

class MIDIInstrumentPlayer {
    private let engine = AVAudioEngine()

    private struct SamplerWithMixer {
        let sampler: AVAudioUnitSampler
        let mixer: AVAudioMixerNode
    }

    private var samplers: [UInt8: SamplerWithMixer] = [:]

    private struct ActiveNote {
        let timer: DispatchSourceTimer
        let mixer: AVAudioMixerNode
    }

    private var activeNotes: [String: ActiveNote] = [:]
    
    private let activeNotesQueue = DispatchQueue(label: "com.echosight.MIDIInstrumentPlayer.activeNotesQueue")

    init() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)

            // try engine.start()
        } catch {
            print("Audio engine failed to start: \(error.localizedDescription)")
        }
    }

    private func getOrCreateSampler(for program: UInt8, pan: Float) -> AVAudioUnitSampler {
        if let existing = samplers[program] {
            existing.mixer.pan = pan
            return existing.sampler
        }

        let sampler = AVAudioUnitSampler()
        let mixer = AVAudioMixerNode()
        mixer.pan = pan

        engine.attach(sampler)
        engine.attach(mixer)
        engine.connect(sampler, to: mixer, format: nil)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)

        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                print("Audio engine failed to start even after connection: \(error.localizedDescription)")
            }
        }
        
        let bankURL = Bundle.main.url(forResource: "FluidR3_GM", withExtension: "sf2")!
        try? sampler.loadSoundBankInstrument(at: bankURL, program: program, bankMSB: 0x79, bankLSB: 0x00)
        
        samplers[program] = SamplerWithMixer(sampler: sampler, mixer: mixer)
        return sampler
    }
    
    func playNote(program: UInt8, note: UInt8, duration: TimeInterval, pan: Float = 0.0, velocity: UInt8 = 100) {
        let noteKey = "\(program)-\(note)"
        
        activeNotesQueue.sync {
            if let existing = activeNotes[noteKey] {
                // Update pan and timer
                existing.mixer.pan = pan
                existing.timer.cancel()
                
                let newTimer = DispatchSource.makeTimerSource()
                newTimer.schedule(deadline: .now() + duration)
                newTimer.setEventHandler { [weak self] in
                    self?.activeNotesQueue.async {
                        self?.samplers[program]?.sampler.stopNote(note, onChannel: 0)
                        self?.activeNotes.removeValue(forKey: noteKey)
                    }
                }
                activeNotes[noteKey] = ActiveNote(timer: newTimer, mixer: existing.mixer)
                newTimer.resume()
                return
            }
        }
        
        // If note not playing, start it
        let sampler = getOrCreateSampler(for: program, pan: pan)
        
        if activeNotes[noteKey] != nil {
            return // additional guard ***TODO*** this should not be needed.
        }
        
        sampler.startNote(note, withVelocity: velocity, onChannel: 0)
        
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + duration)
        timer.setEventHandler { [weak self] in
            self?.activeNotesQueue.async {
                self?.samplers[program]?.sampler.stopNote(note, onChannel: 0)
                self?.activeNotes.removeValue(forKey: noteKey)
            }
        }
        
        activeNotesQueue.async { [weak self] in
            if let mixer = self?.samplers[program]?.mixer {
                self?.activeNotes[noteKey] = ActiveNote(timer: timer, mixer: mixer)
            }
        }
        
        timer.resume()
    }


    func playNoteFromPixel(x: CGFloat, y: CGFloat, screenWidth: CGFloat, screenHeight: CGFloat, instrument: UInt8, duration: TimeInterval) {
        let clampedX = min(max(x, 0), screenWidth)
        let clampedY = min(max(y, 0), screenHeight)
        
        let xFraction = clampedX / screenWidth
        let yFraction = 1.0 - (clampedY / screenHeight)

        let pan = Float(xFraction * 2.0 - 1.0)

        let minNote: UInt8 = 12  // C3
        let maxNote: UInt8 = 84  // C6
        let note = UInt8(Double(minNote) + Double(maxNote - minNote) * Double(yFraction))

        playNote(program: instrument, note: note, duration: duration, pan: pan)
    }
}


