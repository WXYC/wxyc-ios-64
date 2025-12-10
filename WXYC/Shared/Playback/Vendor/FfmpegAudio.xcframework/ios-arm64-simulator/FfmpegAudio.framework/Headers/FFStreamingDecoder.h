#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>

/**
 * Opaque handle to an FFmpeg-based streaming audio decoder.
 */
typedef struct FFStreamingDecoder FFStreamingDecoder;

/**
 * Opens an audio stream from the given URL.
 *
 * @param url The URL to stream from (http://, https://, or file://)
 * @return A decoder handle, or NULL on failure
 */
FFStreamingDecoder *ffsd_open(const char *url);

/**
 * Closes the decoder and releases all resources.
 *
 * @param decoder The decoder handle (may be NULL)
 */
void ffsd_close(FFStreamingDecoder *decoder);

/**
 * Gets the sample rate of the output audio (always 48000).
 *
 * @param decoder The decoder handle
 * @return Sample rate in Hz
 */
int ffsd_get_sample_rate(FFStreamingDecoder *decoder);

/**
 * Gets the number of output channels (always 2 for stereo).
 *
 * @param decoder The decoder handle
 * @return Number of channels
 */
int ffsd_get_channels(FFStreamingDecoder *decoder);

/**
 * Returns whether the output is interleaved (always false - planar output).
 *
 * @param decoder The decoder handle
 * @return false (planar Float32 format)
 */
bool ffsd_get_is_interleaved(FFStreamingDecoder *decoder);

/**
 * Decodes the next chunk of audio.
 *
 * Output format: Float32 planar, 48kHz, stereo
 *
 * @param decoder   The decoder handle
 * @param outData   Receives pointer to array of channel pointers (2 channels)
 *                  Memory is owned by the decoder and valid until next call
 * @param outFrames Receives number of frames decoded
 * @return >0 on success (number of frames), 0 on EOF, <0 on error
 */
int ffsd_decode_next(FFStreamingDecoder *decoder,
                     const float ***outData,
                     int *outFrames);

#ifdef __cplusplus
}
#endif
