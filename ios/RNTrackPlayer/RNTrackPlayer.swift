//
//  RNTrackPlayer.swift
//  RNTrackPlayer
//
//  Created by David Chavez on 13.08.17.
//  Copyright © 2017 David Chavez. All rights reserved.
//

import Foundation
import MediaPlayer

@objc(RNTrackPlayer)
public class RNTrackPlayer: RCTEventEmitter {
    
    // MARK: - Attributes
    
    private var hasInitialized = false

    private lazy var player: QueuedAudioPlayer = {
        let player = QueuedAudioPlayer()
        player.bufferDuration = 1

        // disable auto advance, so that we can control the order of
        // operations in order to send accurate event data
        player.automaticallyLoadNextSong = false

        return player
    }()
    
    // MARK: - Lifecycle Methods
    
    deinit {
        reset(resolve: { _ in }, reject: { _, _, _  in })
    }
    
    // MARK: - RCTEventEmitter
    
    override public static func requiresMainQueueSetup() -> Bool {
        return true;
    }
    
    override public var methodQueue: DispatchQueue! {
        return DispatchQueue.main
    }
    
    @objc(constantsToExport)
    override public func constantsToExport() -> [AnyHashable: Any] {
        return [
            "STATE_NONE": AVPlayerWrapperState.idle.rawValue,
            "STATE_READY": AVPlayerWrapperState.ready.rawValue,
            "STATE_PLAYING": AVPlayerWrapperState.playing.rawValue,
            "STATE_PAUSED": AVPlayerWrapperState.paused.rawValue,
            "STATE_STOPPED": AVPlayerWrapperState.idle.rawValue,
            "STATE_BUFFERING": AVPlayerWrapperState.loading.rawValue,
            
            "TRACK_PLAYBACK_ENDED_REASON_END": PlaybackEndedReason.playedUntilEnd.rawValue,
            "TRACK_PLAYBACK_ENDED_REASON_JUMPED": PlaybackEndedReason.jumpedToIndex.rawValue,
            "TRACK_PLAYBACK_ENDED_REASON_NEXT": PlaybackEndedReason.skippedToNext.rawValue,
            "TRACK_PLAYBACK_ENDED_REASON_PREVIOUS": PlaybackEndedReason.skippedToPrevious.rawValue,
            "TRACK_PLAYBACK_ENDED_REASON_STOPPED": PlaybackEndedReason.playerStopped.rawValue,
            
            "PITCH_ALGORITHM_LINEAR": PitchAlgorithm.linear.rawValue,
            "PITCH_ALGORITHM_MUSIC": PitchAlgorithm.music.rawValue,
            "PITCH_ALGORITHM_VOICE": PitchAlgorithm.voice.rawValue,
            
            "CAPABILITY_PLAY": Capability.play.rawValue,
            "CAPABILITY_PLAY_FROM_ID": "NOOP",
            "CAPABILITY_PLAY_FROM_SEARCH": "NOOP",
            "CAPABILITY_PAUSE": Capability.pause.rawValue,
            "CAPABILITY_STOP": Capability.stop.rawValue,
            "CAPABILITY_SEEK_TO": Capability.seek.rawValue,
            "CAPABILITY_SKIP": "NOOP",
            "CAPABILITY_SKIP_TO_NEXT": Capability.next.rawValue,
            "CAPABILITY_SKIP_TO_PREVIOUS": Capability.previous.rawValue,
            "CAPABILITY_SET_RATING": "NOOP",
            "CAPABILITY_JUMP_FORWARD": Capability.jumpForward.rawValue,
            "CAPABILITY_JUMP_BACKWARD": Capability.jumpBackward.rawValue,
            "CAPABILITY_LIKE": Capability.like.rawValue,
            "CAPABILITY_DISLIKE": Capability.dislike.rawValue,
            "CAPABILITY_BOOKMARK": Capability.bookmark.rawValue,
            
            "REPEAT_MODE_NONE": AudioPlayerRepeatMode.none.rawValue,
            "REPEAT_MODE_QUEUE": AudioPlayerRepeatMode.queue.rawValue,
            "REPEAT_MODE_TRACK": AudioPlayerRepeatMode.track.rawValue,
        ]
    }
    
    @objc(supportedEvents)
    override public func supportedEvents() -> [String] {
        return [
            "playback-queue-ended",
            "playback-state",
            "playback-error",
            "playback-track-changed",
            
            "remote-stop",
            "remote-pause",
            "remote-play",
            "remote-duck",
            "remote-next",
            "remote-seek",
            "remote-previous",
            "remote-jump-forward",
            "remote-jump-backward",
            "remote-like",
            "remote-dislike",
            "remote-bookmark",
            "remote-change-repeat-mode",
            
            "repeat-mode-changed",
        ]
    }
    
    func setupInterruptionHandling() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self)
        notificationCenter.addObserver(self,
                                       selector: #selector(handleInterruption),
                                       name: AVAudioSession.interruptionNotification,
                                       object: nil)
    }
    
    @objc func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
        }
        if type == .began {
            // Interruption began, take appropriate actions
            self.sendEvent(withName: "remote-duck", body: [
                "paused": true
                ])
        }
        else if type == .ended {
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // Interruption Ended - playback should resume
                    self.sendEvent(withName: "remote-duck", body: [
                        "paused": false
                        ])
                } else {
                    // Interruption Ended - playback should NOT resume
                    self.sendEvent(withName: "remote-duck", body: [
                        "permanent": true
                        ])
                }
            }
        }
    }

    // MARK: - Bridged Methods
    
    @objc(setupPlayer:resolver:rejecter:)
    public func setupPlayer(config: [String: Any], resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        if hasInitialized {
            resolve(NSNull())
            return
        }
        
        setupInterruptionHandling();

        // configure if player waits to play
        let autoWait: Bool = config["waitForBuffer"] as? Bool ?? false
        player.automaticallyWaitsToMinimizeStalling = autoWait
        
        // configure if control center metdata should auto update
        let autoUpdateMetadata: Bool = config["autoUpdateMetadata"] as? Bool ?? true
        player.automaticallyUpdateNowPlayingInfo = autoUpdateMetadata
        
        // configure audio session - category, options & mode
        var sessionCategory: AVAudioSession.Category = .playback
        var sessionCategoryOptions: AVAudioSession.CategoryOptions = []
        var sessionCategoryMode: AVAudioSession.Mode = .default
        
        if
            let sessionCategoryStr = config["iosCategory"] as? String,
            let mappedCategory = SessionCategory(rawValue: sessionCategoryStr) {
            sessionCategory = mappedCategory.mapConfigToAVAudioSessionCategory()
        }
        
        let sessionCategoryOptsStr = config["iosCategoryOptions"] as? [String]
        let mappedCategoryOpts = sessionCategoryOptsStr?.compactMap { SessionCategoryOptions(rawValue: $0)?.mapConfigToAVAudioSessionCategoryOptions() } ?? []
        sessionCategoryOptions = AVAudioSession.CategoryOptions(mappedCategoryOpts)
        
        if
            let sessionCategoryModeStr = config["iosCategoryMode"] as? String,
            let mappedCategoryMode = SessionCategoryMode(rawValue: sessionCategoryModeStr) {
            sessionCategoryMode = mappedCategoryMode.mapConfigToAVAudioSessionCategoryMode()
        }
        
        try? AVAudioSession.sharedInstance().setCategory(sessionCategory, mode: sessionCategoryMode, options: sessionCategoryOptions)
        
        // Configure seek tolerances
        if let seekToleranceBefore = config["seekToleranceBefore"] as? Double {
            player.seekToleranceBefore = seekToleranceBefore > 0 ?
                CMTimeMakeWithSeconds(seekToleranceBefore, preferredTimescale: 1000) : .zero
        }
        
        if let seekToleranceAfter = config["seekToleranceAfter"] as? Double {
            player.seekToleranceAfter = seekToleranceAfter > 0 ?
                CMTimeMakeWithSeconds(seekToleranceAfter, preferredTimescale: 1000) : .zero
        }
        
        // setup event listeners
        player.event.stateChange.addListener(self) { [weak self] state in
            self?.sendEvent(withName: "playback-state", body: ["state": state.rawValue])
        }
        
        player.event.fail.addListener(self) { [weak self] error in
            self?.sendEvent(withName: "playback-error", body: ["error": error?.localizedDescription])
        }
        
        player.event.playbackEnd.addListener(self) { [weak self] (reason, currentItem, currentTime, nextItem) in
            guard let `self` = self else { return }

            if reason == .playedUntilEnd {
                // we ignore .skippedToNext and only fire an event
                // for .playedUntilEnd
                // nextTrack might be nil if there are no more, but still send the event for consistency
                self.sendEvent(withName: "playback-track-changed", body: [
                    "track": (currentItem as? Track)?.id as Any,
                    "position": currentTime as Any,
                    "nextTrack": (nextItem as? Track)?.id as Any,
                    ])
                
                if nextItem == nil {
                    // fire an event for the queue ending
                    self.sendEvent(withName: "playback-queue-ended", body: [
                        "track": (currentItem as? Track)?.id as Any,
                        "position": currentTime as Any,
                        ])
                } else {
                    // we are not using automaticallyPlayNextSong on the player in order
                    // to be in control of specifically when the above events are sent
                    // so, attempt to go to the next track now

                    // This is really important, ONLY ACCESS THE PLAYER ON THE MAIN THREAD!!
                    DispatchQueue.main.async {
                        // also make sure that we're not supposed to repeat the current track first
                        if self.player.repeatMode != .track {
                            try? self.player.next()
                        }
                    }
                }
            }

        }
        
        player.remoteCommandController.handleChangePlaybackPositionCommand = { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.sendEvent(withName: "remote-seek", body: ["position": event.positionTime])
                return MPRemoteCommandHandlerStatus.success
            }
            
            return MPRemoteCommandHandlerStatus.commandFailed
        }
        
        player.remoteCommandController.handleNextTrackCommand = { [weak self] _ in
            self?.sendEvent(withName: "remote-next", body: nil)
            return MPRemoteCommandHandlerStatus.success
        }
        
        player.remoteCommandController.handlePauseCommand = { [weak self] _ in
            self?.sendEvent(withName: "remote-pause", body: nil)
            return MPRemoteCommandHandlerStatus.success
        }
        
        player.remoteCommandController.handlePlayCommand = { [weak self] _ in
            self?.sendEvent(withName: "remote-play", body: nil)
            return MPRemoteCommandHandlerStatus.success
        }
        
        player.remoteCommandController.handlePreviousTrackCommand = { [weak self] _ in
            self?.sendEvent(withName: "remote-previous", body: nil)
            return MPRemoteCommandHandlerStatus.success
        }
        
        player.remoteCommandController.handleSkipBackwardCommand = { [weak self] event in
            if let command = event.command as? MPSkipIntervalCommand,
                let interval = command.preferredIntervals.first {
                self?.sendEvent(withName: "remote-jump-backward", body: ["interval": interval])
                return MPRemoteCommandHandlerStatus.success
            }
            
            return MPRemoteCommandHandlerStatus.commandFailed
        }
        
        player.remoteCommandController.handleSkipForwardCommand = { [weak self] event in
            if let command = event.command as? MPSkipIntervalCommand,
                let interval = command.preferredIntervals.first {
                self?.sendEvent(withName: "remote-jump-forward", body: ["interval": interval])
                return MPRemoteCommandHandlerStatus.success
            }
            
            return MPRemoteCommandHandlerStatus.commandFailed
        }
        
        player.remoteCommandController.handleStopCommand = { [weak self] _ in
            self?.sendEvent(withName: "remote-stop", body: nil)
            return MPRemoteCommandHandlerStatus.success
        }
        
        player.remoteCommandController.handleTogglePlayPauseCommand = { [weak self] _ in
            if self?.player.playerState == .paused {
                self?.sendEvent(withName: "remote-play", body: nil)
                return MPRemoteCommandHandlerStatus.success
            }
            
            self?.sendEvent(withName: "remote-pause", body: nil)
            return MPRemoteCommandHandlerStatus.success
        }
        
        player.remoteCommandController.handleLikeCommand = { [weak self] _ in
            self?.sendEvent(withName: "remote-like", body: nil)
            return MPRemoteCommandHandlerStatus.success
        }
        
        player.remoteCommandController.handleDislikeCommand = { [weak self] _ in
            self?.sendEvent(withName: "remote-dislike", body: nil)
            return MPRemoteCommandHandlerStatus.success
        }
        
        player.remoteCommandController.handleBookmarkCommand = { [weak self] _ in
            self?.sendEvent(withName: "remote-bookmark", body: nil)
            return MPRemoteCommandHandlerStatus.success
        }
        
        player.remoteCommandController.handleChangeRepeatModeCommand = { [weak self] event in
            self?.sendEvent(withName: "remote-change-repeat-mode", body: nil)
            return MPRemoteCommandHandlerStatus.success
        }
        
        hasInitialized = true
        resolve(NSNull())
    }
    
    @objc(destroy)
    public func destroy() {
        print("Destroying player")
    }
    
    @objc(updateOptions:resolver:rejecter:)
    public func update(options: [String: Any], resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        if let capabilitiesStr = options["capabilities"] as? [String] {
            let capabilities = capabilitiesStr.compactMap { Capability(rawValue: $0) }
            
            let remoteCommands = capabilities.map { capability in
                capability.mapToPlayerCommand(jumpInterval: options["jumpInterval"] as? NSNumber,
                                              likeOptions: options["likeOptions"] as? [String: Any],
                                              dislikeOptions: options["dislikeOptions"] as? [String: Any],
                                              bookmarkOptions: options["bookmarkOptions"] as? [String: Any])
            }

            player.remoteCommands = remoteCommands
        }
        
        if let automaticallyPlayWhenReady = options["automaticallyPlayWhenReady"] as? Bool {
            player.automaticallyPlayWhenReady = automaticallyPlayWhenReady
        }
        
        if let seekToleranceBefore = options["seekToleranceBefore"] as? Double {
            player.seekToleranceBefore = seekToleranceBefore > 0 ?
                CMTimeMakeWithSeconds(seekToleranceBefore, preferredTimescale: 1000) : .zero
        }
        
        if let seekToleranceAfter = options["seekToleranceAfter"] as? Double {
            player.seekToleranceAfter = seekToleranceAfter > 0 ?
                CMTimeMakeWithSeconds(seekToleranceAfter, preferredTimescale: 1000) : .zero
        }
        
        resolve(NSNull())
    }
    
    @objc(add:before:resolver:rejecter:)
    public func add(trackDicts: [[String: Any]], before trackId: String?, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UIApplication.shared.beginReceivingRemoteControlEvents();
        }
        
        var tracks = [Track]()
        for trackDict in trackDicts {
            guard let track = Track(dictionary: trackDict) else {
                reject("invalid_track_object", "Track is missing a required key", nil)
                return
            }
            
            tracks.append(track)
        }
        
        print("Adding tracks:", tracks)
        
        if let trackId = trackId {
            guard let insertIndex = player.queueManager.items.firstIndex(where: { ($0 as! Track).id == trackId })
                else {
                    reject("track_not_in_queue", "Given track ID was not found in queue", nil)
                    return
            }
            
            try? player.add(items: tracks, at: insertIndex)
        } else {
            if let nextTrack = tracks.first, player.currentItem == nil {
                sendEvent(withName: "playback-track-changed", body: [
                    "track": nil,
                    "position": 0,
                    "nextTrack": nextTrack.id
                    ])
            }
            
            try? player.add(items: tracks)
        }
        
        resolve(NSNull())
    }
    
    @objc(remove:resolver:rejecter:)
    public func remove(tracks ids: [String], resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Removing tracks:", ids)
        var indexesToRemove: [Int] = []
        
        for id in ids {
            if let index = player.queueManager.items.firstIndex(where: { ($0 as! Track).id == id }) {
                if index == player.queueManager.currentIndex { return }
                indexesToRemove.append(index)
            }
        }
        
        for index in indexesToRemove {
            try? player.removeItem(at: index)
        }
        
        resolve(NSNull())
    }
    
    @objc(removeUpcomingTracks:rejecter:)
    public func removeUpcomingTracks(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Removing upcoming tracks")
        player.removeUpcomingItems()
        resolve(NSNull())
    }
    
    func downgradeRepeatMode() {
        /// Downgrades to `.queue` if the user manually skips the repeated track
        if player.repeatMode == .track {
            print("Manual skip, downgrading repeat mode")
            sendEvent(withName: "repeat-mode-changed", body: [
                "repeatMode": AudioPlayerRepeatMode.queue.rawValue as Any
                ])
            player.repeatMode = .queue
        }
    }
    
    @objc(skip:resolver:rejecter:)
    public func skip(to trackId: String, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        guard let trackIndex = player.queueManager.items.firstIndex(where: { ($0 as! Track).id == trackId })
            else {
                reject("track_not_in_queue", "Given track ID was not found in queue", nil)
                return
        }
        
        sendEvent(withName: "playback-track-changed", body: [
            "track": (player.currentItem as? Track)?.id as Any,
            "position": player.currentTime as Any,
            "nextTrack": trackId as Any,
            ])
        
        print("Skipping to track:", trackId)
        downgradeRepeatMode()
        try? player.jumpToItem(atIndex: trackIndex)
        resolve(NSNull())
    }
    
    @objc(skipToNext:rejecter:)
    public func skipToNext(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Skipping to next track")
        do {
            sendEvent(withName: "playback-track-changed", body: [
                "track": (player.currentItem as? Track)?.id as Any,
                "position": player.currentTime as Any,
                "nextTrack": (player.nextItem as? Track)?.id as Any,
                ])

            downgradeRepeatMode()
            try player.next()
            resolve(NSNull())
        } catch (_) {
            reject("queue_exhausted", "There's no tracks left to play", nil)
        }
    }
    
    @objc(skipToPrevious:resolver:rejecter:)
    public func skipToPrevious(_ rewindWhenLte: Double = 0, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        if (rewindWhenLte > 0 && player.currentTime >= rewindWhenLte) || player.previousItem == nil {
            print("Rewinding to start of track")
            player.seek(to: 0)
            resolve(NSNull())
        } else {
            print("Skipping to previous track")
            do {
                sendEvent(withName: "playback-track-changed", body: [
                    "track": (player.currentItem as? Track)?.id as Any,
                    "position": player.currentTime as Any,
                    "nextTrack": (player.previousItem as? Track)?.id as Any,
                    ])
                
                downgradeRepeatMode()
                try player.previous()
                resolve(NSNull())
            } catch (_) {
                reject("no_previous_track", "There's no previous track", nil)
            }
        }
    }
    
    @objc(reset:rejecter:)
    public func reset(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Resetting player.")
        player.stop()
        sendEvent(withName: "repeat-mode-changed", body: [
            "repeatMode": AudioPlayerRepeatMode.none.rawValue as Any
        ])
        player.repeatMode = .none
        resolve(NSNull())
        DispatchQueue.main.async {
            UIApplication.shared.endReceivingRemoteControlEvents();
        }
    }
    
    @objc(play:rejecter:)
    public func play(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Starting/Resuming playback")
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        resolve(NSNull())
    }
    
    @objc(pause:rejecter:)
    public func pause(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Pausing playback")
        player.pause()
        resolve(NSNull())
    }
    
    @objc(stop:rejecter:)
    public func stop(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Stopping playback")
        player.stop()
        resolve(NSNull())
    }
    
    @objc(seekTo:resolver:rejecter:)
    public func seek(to time: Double, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Seeking to \(time) seconds")
        player.seek(to: time)
        resolve(NSNull())
    }
    
    @objc(setVolume:resolver:rejecter:)
    public func setVolume(level: Float, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Setting volume to \(level)")
        player.volume = level
        resolve(NSNull())
    }
    
    @objc(getVolume:rejecter:)
    public func getVolume(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Getting current volume")
        resolve(player.volume)
    }
    
    @objc(setRate:resolver:rejecter:)
    public func setRate(rate: Float, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Setting rate to \(rate)")
        player.rate = rate
        resolve(NSNull())
    }
    
    @objc(getRate:rejecter:)
    public func getRate(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Getting current rate")
        resolve(player.rate)
    }
    
    @objc(setRepeatMode:resolver:rejecter:)
    public func setRepeat(mode: String, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Setting repeat mode to \(mode)")
        guard let repeatMode = AudioPlayerRepeatMode(rawValue: mode) else {
            reject("invalid_repeat_mode", "Given mode: \(mode) is invalid", nil)
            return
        }
        sendEvent(withName: "repeat-mode-changed", body: [
            "repeatMode": repeatMode.rawValue as Any
            ])
        player.repeatMode = repeatMode
        resolve(NSNull())
    }
    
    @objc(getRepeatMode:rejecter:)
    public func getRepeatMode(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Getting current repeat mode")
        resolve(player.repeatMode.rawValue)
    }
    
    @objc(setPlayWhenReady:resolver:rejecter:)
    public func setPlayWhenReady(autoplay: Bool, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Setting PlayWhenReady to: \(autoplay)")
        player.automaticallyPlayWhenReady = autoplay
        resolve(NSNull())
    }
    
    @objc(getPlayWhenReady:rejecter:)
    public func getPlayWhenReady(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Getting PlayWhenReady")
        resolve(player.automaticallyPlayWhenReady)
    }
    
    @objc(getTrack:resolver:rejecter:)
    public func getTrack(id: String, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        guard let track = player.queueManager.items.first(where: { ($0 as! Track).id == id })
            else {
                reject("track_not_in_queue", "Given track ID was not found in queue", nil)
                return
        }
        
        resolve((track as? Track)?.toObject())
    }
    
    @objc(getQueue:rejecter:)
    public func getQueue(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        let serializedQueue = player.queueManager.items.map { ($0 as! Track).toObject() }
        resolve(serializedQueue)
    }
    
    @objc(getCurrentTrack:rejecter:)
    public func getCurrentTrack(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve((player.currentItem as? Track)?.id)
    }
    
    @objc(getDuration:rejecter:)
    public func getDuration(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(player.duration)
    }
    
    @objc(getBufferedPosition:rejecter:)
    public func getBufferedPosition(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(player.bufferedPosition)
    }
    
    @objc(getPosition:rejecter:)
    public func getPosition(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(player.currentTime)
    }
    
    @objc(getState:rejecter:)
    public func getState(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(player.playerState.rawValue)
    }
    
    @objc(updateMetadataForTrack:metadata:resolver:rejecter:)
    public func updateMetadata(for trackId: String, metadata: [String: Any], resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        guard let track = player.queueManager.items.first(where: { ($0 as! Track).id == trackId }) as? Track
            else {
                reject("track_not_in_queue", "Given track ID was not found in queue", nil)
                return
        }
        
        track.updateMetadata(dictionary: metadata)
        if (player.currentItem as! Track).id == track.id {
            Metadata.update(for: player, with: metadata)
        }
        resolve(NSNull())
    }
    
    @objc(clearNowPlayingMetadata:rejecter:)
    public func clearNowPlayingMetadata(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        player.nowPlayingInfoController.clear()
        resolve(NSNull())
    }
    
    @objc(updateNowPlayingMetadata:resolver:rejecter:)
    public func updateNowPlayingMetadata(metadata: [String: Any], resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        Metadata.update(for: player, with: metadata)
        resolve(NSNull())
    }
}
