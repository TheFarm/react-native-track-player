import * as React from 'react'
import { NavigationContainer } from '@react-navigation/native'
import { createNativeStackNavigator } from 'react-native-screens/native-stack'
import { enableScreens } from 'react-native-screens'

import LandingScreen from './react/screens/LandingScreen'
import PlaylistScreen from './react/screens/PlaylistScreen'
enableScreens()

const MainStack = createNativeStackNavigator()

export const MainStackScreen = () => {
  return (
    <MainStack.Navigator>
      <MainStack.Screen name="Landing" component={LandingScreen} />
      <MainStack.Screen name="Playlist" component={PlaylistScreen} />
    </MainStack.Navigator>
  )
}

export default function App() {
  return (
    <NavigationContainer>
      <MainStackScreen />
    </NavigationContainer>
  )
}
