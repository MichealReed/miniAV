#ifdef _WIN32
#  ifdef MINIAV_BUILD_DLL
#    define MINIAV_API __declspec(dllexport)
#  else
#    define MINIAV_API __declspec(dllimport)
#  endif
#elif defined(__EMSCRIPTEN__)
#  include <emscripten.h>
#  define MINIAV_API EMSCRIPTEN_KEEPALIVE
#else
#  define MINIAV_API
#endif