cmake_minimum_required(VERSION 3.22)

project(AmbisonicLoudnessMeter VERSION 1.0.0 LANGUAGES C CXX)

# JUCE-Framework einbinden: -DJUCE_DIR=/pfad/zu/JUCE oder JUCE als Unterordner
# von plugin/ (wird von scripts/build-ambisonic-plugin.sh automatisch geholt)
if(NOT DEFINED JUCE_DIR)
    set(JUCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/JUCE" CACHE PATH "Pfad zum JUCE-Framework")
endif()
if(NOT EXISTS "${JUCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR
        "JUCE nicht gefunden unter '${JUCE_DIR}'.\n"
        "Bitte -DJUCE_DIR=/pfad/zu/JUCE setzen oder siehe scripts/build-ambisonic-plugin.sh")
endif()
add_subdirectory("${JUCE_DIR}" "${CMAKE_BINARY_DIR}/JUCE" EXCLUDE_FROM_ALL)

if(APPLE)
    set(PLUGIN_FORMATS AU VST3)
else()
    set(PLUGIN_FORMATS VST3)
endif()

juce_add_plugin(ambisonic-loudness-meter
    COMPANY_NAME            "seren-a"
    PLUGIN_MANUFACTURER_CODE SrnA
    PLUGIN_CODE             AmLM
    FORMATS                 ${PLUGIN_FORMATS}
    PRODUCT_NAME            "Ambisonic Loudness Meter"
    BUNDLE_ID               "com.seren-a.ambisonic-loudness-meter"
    IS_SYNTH                FALSE
    NEEDS_MIDI_INPUT        FALSE
    NEEDS_MIDI_OUTPUT       FALSE
    IS_MIDI_EFFECT          FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS FALSE
    COPY_PLUGIN_AFTER_BUILD FALSE
    AU_MAIN_TYPE            kAudioUnitType_Effect
    VST3_CATEGORIES         "Analysis"
)

target_sources(ambisonic-loudness-meter PRIVATE
    src/PluginProcessor.cpp
    src/PluginEditor.cpp
)

target_include_directories(ambisonic-loudness-meter PRIVATE src)

target_compile_definitions(ambisonic-loudness-meter PUBLIC
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_VST3_HOST_CROSS_PLATFORM_UID=1
    JUCE_VST3_CAN_REPLACE_VST2=0
    JUCE_DISPLAY_SPLASH_SCREEN=0
)

target_link_libraries(ambisonic-loudness-meter PRIVATE
    juce::juce_audio_processors
    juce::juce_audio_utils
    juce::juce_gui_extra
    juce::juce_recommended_config_flags
    juce::juce_recommended_lto_flags
    juce::juce_recommended_warning_flags
)

# JUCE-unabhaengige Referenztests des DSP-Kerns (ohne JUCE kompilierbar,
# validiert gegen die pytest-Referenzwerte des Python-Kerns):
add_executable(dsp_tests src/dsp/DspTests.cpp)
target_include_directories(dsp_tests PRIVATE src/dsp)
target_compile_features(dsp_tests PRIVATE cxx_std_17)
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(dsp_tests PRIVATE -O2 -Wall)
endif()

# End-to-End-Smoke-Test des Processors (headless, ohne Editor):
juce_add_console_app(plugin_smoke_test)
target_sources(plugin_smoke_test PRIVATE
    src/PluginSmokeTest.cpp
    src/PluginProcessor.cpp
    src/PluginEditor.cpp
)
target_include_directories(plugin_smoke_test PRIVATE src)
target_compile_definitions(plugin_smoke_test PRIVATE
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_DISPLAY_SPLASH_SCREEN=0
)
target_link_libraries(plugin_smoke_test PRIVATE
    juce::juce_audio_processors
    juce::juce_gui_extra
    juce::juce_recommended_config_flags
)
