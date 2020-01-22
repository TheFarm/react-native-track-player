import { State, Event, RepeatMode } from './index';
/** Get current playback state and subsequent updates  */
export declare const usePlaybackState: () => State;
/** Get current repeat mode and subsequent updates  */
export declare const useRepeatMode: () => RepeatMode;
declare type Handler = (payload: {
    type: Event;
    [key: string]: any;
}) => void;
/**
 * Attaches a handler to the given TrackPlayer events and performs cleanup on unmount
 * @param events - TrackPlayer events to subscribe to
 * @param handler - callback invoked when the event fires
 */
export declare const useTrackPlayerEvents: (events: Event[], handler: Handler) => void;
/**
 * Poll for track progress for the given interval (in milliseconds)
 * @param interval - ms interval
 */
export declare function useProgress(updateInterval?: number): {
    position: number;
    duration: number;
    buffered: number;
};
export {};
