#ifndef FLUTTER_PLUGIN_SRT_DART_PLUGIN_H_
#define FLUTTER_PLUGIN_SRT_DART_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace srt_dart {

class SrtDartPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  SrtDartPlugin();

  virtual ~SrtDartPlugin();

  // Disallow copy and assign.
  SrtDartPlugin(const SrtDartPlugin&) = delete;
  SrtDartPlugin& operator=(const SrtDartPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace srt_dart

#endif  // FLUTTER_PLUGIN_SRT_DART_PLUGIN_H_
