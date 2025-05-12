import os
import azure.cognitiveservices.speech as speechsdk

def synthesize_speech_to_speaker(text_to_speak, voice_name="en-GB-LibbyNeural"): # MODIFIED HERE
    """Synthesizes speech from text and speaks it out on the default speaker.

    Args:
        text_to_speak (str): The text to synthesize.
        voice_name (str, optional): The voice to use.
                                    Defaults to "en-GB-LibbyNeural". # MODIFIED HERE
                                    Find more voices here:
                                    https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts
    """
    try:
        speech_key = os.environ.get('SPEECH_KEY')
        speech_region = os.environ.get('SPEECH_REGION')

        if not speech_key or not speech_region:
            print("ERROR: Environment variables SPEECH_KEY or SPEECH_REGION not set.")
            return "Error: Environment variables not set."

        speech_config = speechsdk.SpeechConfig(subscription=speech_key, region=speech_region)
        speech_config.speech_synthesis_voice_name = voice_name
        speech_synthesizer = speechsdk.SpeechSynthesizer(speech_config=speech_config)

        print(f"Synthesizing speech for text: [{text_to_speak}] with voice: [{voice_name}]")
        result = speech_synthesizer.speak_text_async(text_to_speak).get()

        if result.reason == speechsdk.ResultReason.SynthesizingAudioCompleted:
            print("Speech synthesized to speaker.")
            return "Speech synthesized successfully."
        elif result.reason == speechsdk.ResultReason.Canceled:
            cancellation_details = result.cancellation_details
            print(f"Speech synthesis canceled: {cancellation_details.reason}")
            if cancellation_details.reason == speechsdk.CancellationReason.Error:
                if cancellation_details.error_details:
                    print(f"Error details: {cancellation_details.error_details}")
            return f"Error: Speech synthesis canceled - {cancellation_details.reason}. Details: {cancellation_details.error_details}" # Added error details

    except Exception as ex:
        print(f"An exception occurred: {ex}")
        return f"Error: An exception occurred - {ex}"

def synthesize_speech_to_file(text_to_speak, output_filename="output_audio.wav", voice_name="en-GB-LibbyNeural"):
    try:
        speech_key = os.environ.get('SPEECH_KEY')
        speech_region = os.environ.get('SPEECH_REGION')

        if not speech_key or not speech_region:
            print("ERROR: Environment variables SPEECH_KEY or SPEECH_REGION not set.")
            return "Error: Environment variables not set."

        speech_config = speechsdk.SpeechConfig(subscription=speech_key, region=speech_region)
        speech_config.speech_synthesis_voice_name = voice_name
        
        # --- ADD THIS LINE to specify a common WAV format ---
        speech_config.set_speech_synthesis_output_format(speechsdk.SpeechSynthesisOutputFormat.Riff16Khz16BitMonoPcm)
        # Options include:
        # Riff8Khz16BitMonoPcm
        # Riff16Khz16BitMonoPcm (Commonly well-supported)
        # Riff24Khz16BitMonoPcm
        # Riff48Khz16BitMonoPcm
        # audio-16khz-128kbitrate-mono-mp3 (If you wanted MP3 instead, browser support for MP3 is excellent)
        # --- END ADDED LINE ---

        file_config = speechsdk.audio.AudioOutputConfig(filename=output_filename)
        speech_synthesizer = speechsdk.SpeechSynthesizer(speech_config=speech_config, audio_config=file_config)

        print(f"Synthesizing speech for text: [{text_to_speak}] to file: [{output_filename}] with voice: [{voice_name}] using format Riff16Khz16BitMonoPcm")
        result = speech_synthesizer.speak_text_async(text_to_speak).get()

        if result.reason == speechsdk.ResultReason.SynthesizingAudioCompleted:
            print(f"Speech synthesized and saved to {output_filename}")
            return f"Speech synthesized and saved to {output_filename}"
        elif result.reason == speechsdk.ResultReason.Canceled:
            cancellation_details = result.cancellation_details
            print(f"Speech synthesis canceled: {cancellation_details.reason}")
            if cancellation_details.reason == speechsdk.CancellationReason.Error:
                if cancellation_details.error_details:
                    print(f"Error details: {cancellation_details.error_details}")
            return f"Error: Speech synthesis canceled - {cancellation_details.reason}. Details: {cancellation_details.error_details}"

    except Exception as ex:
        print(f"An exception occurred: {ex}")
        return f"Error: An exception occurred - {ex}"

# Example usage (you can run this Python script directly to test)
if __name__ == '__main__':
    test_text = "Hello"
    print("--- Testing speech to speaker ---")
    speaker_result = synthesize_speech_to_speaker(test_text) # Will use default Libby
    print(f"Speaker synthesis result: {speaker_result}\n")

    # print("--- Testing speech to file ---")
    # file_result = synthesize_speech_to_file(test_text, "test_output_libby.wav") # Will use default Libby
    # print(f"File synthesis result: {file_result}")