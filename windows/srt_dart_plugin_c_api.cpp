#include "include/srt_dart/srt_dart_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "srt_dart_plugin.h"

void SrtDartPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  srt_dart::SrtDartPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
