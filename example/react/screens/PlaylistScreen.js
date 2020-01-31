import React, { useEffect } from 'react'
import { StyleSheet, Text, View } from 'react-native'
import TrackPlayer, { Capability, State, usePlaybackState, RepeatMode } from 'react-native-track-player'

import Player from '../components/Player'
import playlistData from '../data/playlist.json'
import localTrack from '../resources/pure.m4a'

export default function PlaylistScreen() {
  const playbackState = usePlaybackState()

  useEffect(() => {
    TrackPlayer.setupPlayer()
    TrackPlayer.updateOptions({
      stopWithApp: true,
      capabilities: [
        Capability.Play,
        Capability.Pause,
        Capability.SkipToNext,
        Capability.SkipToPrevious,
        Capability.Stop,
      ],
      compactCapabilities: [Capability.Play, Capability.Pause],
      seekToleranceBefore: 0,
      seekToleranceAfter: 0,
    })
  }, [])

  const [playWhenReady, setPlayWhenReady] = React.useState(true)

  async function togglePlayback() {
    const currentTrack = await TrackPlayer.getCurrentTrack()
    if (currentTrack == null) {
      await TrackPlayer.reset()
      await TrackPlayer.add(playlistData)
      await TrackPlayer.add({
        id: 'local-track',
        url: localTrack,
        title: 'Pure (Demo)',
        artist: 'David Chavez',
        artwork: 'https://picsum.photos/200',
        initialTime: 0,
      })
      await TrackPlayer.play()
    } else {
      if (playbackState !== State.Playing) {
        await TrackPlayer.play()
      } else {
        await TrackPlayer.pause()
      }
    }
  }

  async function togglePlayWhenReady() {
    const current = await TrackPlayer.getPlayWhenReady()
    await TrackPlayer.setPlayWhenReady(!current)
    setPlayWhenReady(!current)
  }

  async function toggleRepeatMode() {
    let repeatMode = await TrackPlayer.getRepeatMode()

    switch (repeatMode) {
      case RepeatMode.None:
        repeatMode = RepeatMode.Queue
        break

      case RepeatMode.Queue:
        repeatMode = RepeatMode.Track
        break

      case RepeatMode.Track:
        repeatMode = RepeatMode.None
        break
    }

    await TrackPlayer.setRepeatMode(repeatMode)
  }

  async function seekTo(seconds: number) {
    await TrackPlayer.seekTo(seconds)
    await TrackPlayer.play()
  }

  return (
    <View style={styles.container}>
      <Text style={styles.description}>
        We'll be inserting a playlist into the library loaded from `playlist.json`. We'll also be using the
        `ProgressComponent` which allows us to track playback time.
      </Text>
      <Player
        onNext={skipToNext}
        style={styles.player}
        onPrevious={skipToPrevious}
        onTogglePlayback={togglePlayback}
        onTogglePlayWhenReady={togglePlayWhenReady}
        onToggleRepeatMode={toggleRepeatMode}
        onSeekTo={seekTo}
        playWhenReady={playWhenReady}
      />
      <Text style={styles.state}>{getStateName(playbackState)}</Text>
    </View>
  )
}

PlaylistScreen.navigationOptions = {
  title: 'Playlist Example',
}

function getStateName(state) {
  switch (state) {
    case State.None:
      return 'None'
    case State.Playing:
      return 'Playing'
    case State.Paused:
      return 'Paused'
    case State.Stopped:
      return 'Stopped'
    case State.Buffering:
      return 'Buffering'
    case State.Ready:
      return 'Ready'
    case State.Connecting:
      return 'Connecting'
    default:
      return 'Unknown'
  }
}

async function skipToNext() {
  try {
    await TrackPlayer.skipToNext()
  } catch (_) {}
}

async function skipToPrevious() {
  try {
    // Rewinds if current progress >= 3
    await TrackPlayer.skipToPrevious(3)
  } catch (_) {}
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    backgroundColor: '#F5FCFF',
  },
  description: {
    width: '80%',
    marginTop: 20,
    textAlign: 'center',
  },
  player: {
    marginTop: 40,
  },
  state: {
    marginTop: 20,
  },
})
