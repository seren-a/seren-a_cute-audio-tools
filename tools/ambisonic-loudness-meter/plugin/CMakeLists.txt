cmake_minimum_required(VERSION 3.22)
project(ambisonic-loudness-meter VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)


add_definitions(-DJUCE_WEB_BROWSER=0)

add_subdirectory(JUCE)

juce_add_plugin(ambisonic-loudness-meter
    COMPANY_NAME "seren.a cute-audio-tools"
    BUNDLE_IDENTIFIER "a.seren.cuteaudiotools.ambisonicloudnessmeter"
    PLUGIN_MANUFACTURER_CODE Sera
    PLUGIN_CODE Salm
    FORMATS AU VST3 Standalone
    PRODUCT_NAME "ambisonic-loudness-meter"
    IS_SYNTH FALSE
    NEEDS_MIDI_INPUT FALSE
    NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE
    COPY_PLUGIN_AFTER_BUILD FALSE
    VST3_CATEGORIES Fx Analyser
)

target_sources(ambisonic-loudness-meter PRIVATE
    src/PluginProcessor.cpp
    src/PluginEditor.cpp
)

target_compile_definitions(ambisonic-loudness-meter PUBLIC
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_VST3_CAN_REPLACE_VST2=0
)

