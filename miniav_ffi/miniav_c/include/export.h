#ifdef _WIN32
#  ifdef MINIAV_BUILD_DLL
#    define MINIAV_API __declspec(dllexport)
#  else
#    define MINIAV_API __declspec(dllimport)
#  endif
#else
#  define MINIAV_API
#endif