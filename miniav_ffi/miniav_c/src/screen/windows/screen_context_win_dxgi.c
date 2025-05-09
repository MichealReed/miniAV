// #define COBJMACROS // Enables C-style COM interface calling
// #include "screen_context_win_dxgi.h"
// #include "../../../include/miniav.h"
// #include "../../common/miniav_logging.h"
// #include "../../common/miniav_utils.h"
// #include "../../common/miniav_time.h" // For miniav_get_qpc_microseconds, miniav_get_qpc_frequency

// #include <windows.h>
// #include <d3d11.h>
// #include <dxgi1_2.h> // For IDXGIOutputDuplication
// #include <stdio.h>   // For _snprintf_s

// #pragma comment(lib, "d3d11.lib")
// #pragma comment(lib, "dxgi.lib")

// // Payload for releasing DXGI frame resources
// typedef struct DXGIFrameReleasePayload {
//     ID3D11Texture2D* staging_texture_for_frame; // AddRef'd for this specific frame
//     ID3D11DeviceContext* d3d_context_for_unmap; // Pointer, not AddRef'd per frame (owned by DXGIScreenPlatformContext)
//     UINT subresource_for_unmap;
// } DXGIFrameReleasePayload;


// typedef struct DXGIScreenPlatformContext {
//     MiniAVScreenContext *parent_ctx; // Pointer back to the main MiniAV context

//     IDXGIOutputDuplication* output_duplication;
//     ID3D11Device* d3d_device;
//     ID3D11DeviceContext* d3d_context;
//     ID3D11Texture2D* staging_texture; // General staging texture, or per-frame if needed

//     DXGI_OUTPUT_DESC output_desc;
//     UINT adapter_index_internal;
//     UINT output_index_internal;
//     char selected_device_id[MINIAV_DEVICE_ID_MAX_LEN];


//     MiniAVBufferCallback app_callback_internal;
//     void *app_callback_user_data_internal;

//     BOOL is_streaming;
//     HANDLE capture_thread_handle;
//     HANDLE stop_event_handle;
//     CRITICAL_SECTION critical_section; // For thread-safe access to shared members

//     MiniAVVideoFormatInfo configured_format; // Store user's requested format (FPS mainly)
//     UINT target_fps;
//     UINT frame_width;  // Actual width from DXGI
//     UINT frame_height; // Actual height from DXGI
//     MiniAVPixelFormat pixel_format; // Should be BGRA32 for DXGI

//     LARGE_INTEGER qpc_frequency;

// } DXGIScreenPlatformContext;


// // --- Forward declarations for static functions ---
// static DWORD WINAPI dxgi_capture_thread_proc(LPVOID param);
// static MiniAVResultCode dxgi_init_d3d_and_duplication(DXGIScreenPlatformContext *dxgi_ctx, UINT adapter_idx, UINT output_idx);
// static void dxgi_cleanup_d3d_and_duplication(DXGIScreenPlatformContext *dxgi_ctx);


// // --- Platform Ops Implementation ---

// static MiniAVResultCode dxgi_init_platform(MiniAVScreenContext *ctx) {
//     miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Initializing platform context.");
//     if (!ctx) return MINIAV_ERROR_INVALID_ARG;

//     DXGIScreenPlatformContext *dxgi_ctx = (DXGIScreenPlatformContext *)miniav_calloc(1, sizeof(DXGIScreenPlatformContext));
//     if (!dxgi_ctx) {
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to allocate DXGIScreenPlatformContext.");
//         return MINIAV_ERROR_OUT_OF_MEMORY;
//     }

//     dxgi_ctx->parent_ctx = ctx;
//     ctx->platform_ctx = dxgi_ctx;
//     dxgi_ctx->pixel_format = MINIAV_PIXEL_FORMAT_BGRA32; // Default for DXGI desktop duplication
//     dxgi_ctx->stop_event_handle = CreateEvent(NULL, TRUE, FALSE, NULL); // Manual-reset, initially non-signaled
//     if (dxgi_ctx->stop_event_handle == NULL) {
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to create stop event.");
//         miniav_free(dxgi_ctx);
//         ctx->platform_ctx = NULL;
//         return MINIAV_ERROR_SYSTEM_CALL_FAILED;
//     }

//     if (!InitializeCriticalSectionAndSpinCount(&dxgi_ctx->critical_section, 0x00000400)) {
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to initialize critical section.");
//         CloseHandle(dxgi_ctx->stop_event_handle);
//         miniav_free(dxgi_ctx);
//         ctx->platform_ctx = NULL;
//         return MINIAV_ERROR_SYSTEM_CALL_FAILED;
//     }
    
//     dxgi_ctx->qpc_frequency = miniav_get_qpc_frequency();

//     miniav_log(MINIAV_LOG_LEVEL_INFO, "DXGI: Platform context initialized successfully.");
//     return MINIAV_SUCCESS;
// }

// static MiniAVResultCode dxgi_destroy_platform(MiniAVScreenContext *ctx) {
//     miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Destroying platform context.");
//     if (!ctx || !ctx->platform_ctx) return MINIAV_ERROR_NOT_INITIALIZED;

//     DXGIScreenPlatformContext *dxgi_ctx = (DXGIScreenPlatformContext *)ctx->platform_ctx;

//     if (dxgi_ctx->is_streaming) {
//         miniav_log(MINIAV_LOG_LEVEL_WARN, "DXGI: Platform being destroyed while streaming. Attempting to stop.");
//         // This should have been called by MiniAV_Screen_StopCapture
//         if (dxgi_ctx->stop_event_handle) SetEvent(dxgi_ctx->stop_event_handle);
//         if (dxgi_ctx->capture_thread_handle) {
//             WaitForSingleObject(dxgi_ctx->capture_thread_handle, INFINITE);
//             CloseHandle(dxgi_ctx->capture_thread_handle);
//             dxgi_ctx->capture_thread_handle = NULL;
//         }
//         dxgi_ctx->is_streaming = FALSE;
//     }
    
//     dxgi_cleanup_d3d_and_duplication(dxgi_ctx);

//     if (dxgi_ctx->stop_event_handle) {
//         CloseHandle(dxgi_ctx->stop_event_handle);
//         dxgi_ctx->stop_event_handle = NULL;
//     }
//     DeleteCriticalSection(&dxgi_ctx->critical_section);

//     miniav_free(dxgi_ctx);
//     ctx->platform_ctx = NULL;
//     miniav_log(MINIAV_LOG_LEVEL_INFO, "DXGI: Platform context destroyed.");
//     return MINIAV_SUCCESS;
// }

// static MiniAVResultCode dxgi_enumerate_displays(MiniAVDeviceInfo **displays_out, uint32_t *count_out) {
//     miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Enumerating displays.");
//     if (!displays_out || !count_out) return MINIAV_ERROR_INVALID_ARG;
//     *displays_out = NULL;
//     *count_out = 0;

//     HRESULT hr;
//     IDXGIFactory1* factory = NULL;
//     MiniAVDeviceInfo *result_devices = NULL;
//     uint32_t current_device_count = 0;
//     uint32_t allocated_devices = 0;

//     hr = CreateDXGIFactory1(&IID_IDXGIFactory1, (void**)&factory);
//     if (FAILED(hr)) {
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to create DXGIFactory1: 0x%X", hr);
//         return MINIAV_ERROR_SYSTEM_CALL_FAILED;
//     }

//     IDXGIAdapter1* adapter = NULL;
//     for (UINT i = 0; factory && SUCCEEDED(IDXGIFactory1_EnumAdapters1(factory, i, &adapter)); ++i) {
//         IDXGIOutput* output = NULL;
//         for (UINT j = 0; adapter && SUCCEEDED(IDXGIAdapter1_EnumOutputs(adapter, j, &output)); ++j) {
//             DXGI_OUTPUT_DESC desc;
//             if (SUCCEEDED(IDXGIOutput_GetDesc(output, &desc))) {
//                 if (current_device_count >= allocated_devices) {
//                     allocated_devices = (allocated_devices == 0) ? 4 : allocated_devices * 2;
//                     MiniAVDeviceInfo* new_list = (MiniAVDeviceInfo*)miniav_realloc(result_devices, allocated_devices * sizeof(MiniAVDeviceInfo));
//                     if (!new_list) {
//                         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to reallocate device list.");
//                         miniav_free(result_devices);
//                         if(output) IDXGIOutput_Release(output);
//                         if(adapter) IDXGIAdapter1_Release(adapter);
//                         IDXGIFactory1_Release(factory);
//                         return MINIAV_ERROR_OUT_OF_MEMORY;
//                     }
//                     result_devices = new_list;
//                 }

//                 MiniAVDeviceInfo* current_device_info = &result_devices[current_device_count];
//                 memset(current_device_info, 0, sizeof(MiniAVDeviceInfo));

//                 // Create a unique ID like "Adapter0_Output0"
//                 _snprintf_s(current_device_info->device_id, MINIAV_DEVICE_ID_MAX_LEN, _TRUNCATE, "Adapter%u_Output%u", i, j);
                
//                 // Convert monitor name (WCHAR) to UTF-8
//                 WideCharToMultiByte(CP_UTF8, 0, desc.DeviceName, -1, current_device_info->name, MINIAV_DEVICE_NAME_MAX_LEN, NULL, NULL);
                
//                 current_device_info->is_default = (desc.DesktopCoordinates.left == 0 && desc.DesktopCoordinates.top == 0); // Simplistic default check

//                 current_device_count++;
//             }
//             if(output) IDXGIOutput_Release(output);
//             output = NULL;
//         }
//         if(adapter) IDXGIAdapter1_Release(adapter);
//         adapter = NULL;
//     }

//     if (factory) IDXGIFactory1_Release(factory);

//     *displays_out = result_devices;
//     *count_out = current_device_count;
//     miniav_log(MINIAV_LOG_LEVEL_INFO, "DXGI: Enumerated %u displays.", current_device_count);
//     return MINIAV_SUCCESS;
// }

// static MiniAVResultCode dxgi_enumerate_windows(MiniAVDeviceInfo **windows_out, uint32_t *count_out) {
//     MINIAV_UNUSED(windows_out);
//     MINIAV_UNUSED(count_out);
//     miniav_log(MINIAV_LOG_LEVEL_WARN, "DXGI: EnumerateWindows is not supported by DXGI backend.");
//     return MINIAV_ERROR_NOT_SUPPORTED;
// }


// static MiniAVResultCode dxgi_init_d3d_and_duplication(DXGIScreenPlatformContext *dxgi_ctx, UINT adapter_idx, UINT output_idx) {
//     HRESULT hr;
//     IDXGIFactory1* factory = NULL;
//     IDXGIAdapter1* adapter = NULL;
//     IDXGIOutput* output = NULL;
//     IDXGIOutput1* output1 = NULL;

//     dxgi_cleanup_d3d_and_duplication(dxgi_ctx); // Clean up any previous state

//     hr = CreateDXGIFactory1(&IID_IDXGIFactory1, (void**)&factory);
//     if (FAILED(hr)) {
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to create DXGIFactory1 for duplication: 0x%X", hr);
//         return MINIAV_ERROR_SYSTEM_CALL_FAILED;
//     }

//     if (FAILED(IDXGIFactory1_EnumAdapters1(factory, adapter_idx, &adapter))) {
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to get adapter %u.", adapter_idx);
//         IDXGIFactory1_Release(factory);
//         return MINIAV_ERROR_DEVICE_NOT_FOUND;
//     }

//     D3D_FEATURE_LEVEL feature_levels[] = { D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0 };
//     hr = D3D11CreateDevice(adapter, D3D_DRIVER_TYPE_UNKNOWN, NULL, 0,
//                            feature_levels, ARRAYSIZE(feature_levels),
//                            D3D11_SDK_VERSION, &dxgi_ctx->d3d_device, NULL, &dxgi_ctx->d3d_context);
//     if (FAILED(hr)) {
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: D3D11CreateDevice failed: 0x%X", hr);
//         if(adapter) IDXGIAdapter1_Release(adapter);
//         IDXGIFactory1_Release(factory);
//         return MINIAV_ERROR_SYSTEM_CALL_FAILED;
//     }

//     if (FAILED(IDXGIAdapter1_EnumOutputs(adapter, output_idx, &output))) {
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to get output %u on adapter %u.", output_idx, adapter_idx);
//         dxgi_cleanup_d3d_and_duplication(dxgi_ctx); // Releases D3D device/context
//         if(adapter) IDXGIAdapter1_Release(adapter);
//         IDXGIFactory1_Release(factory);
//         return MINIAV_ERROR_DEVICE_NOT_FOUND;
//     }

//     if (FAILED(IDXGIOutput_QueryInterface(output, &IID_IDXGIOutput1, (void**)&output1))) {
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to query IDXGIOutput1.");
//         dxgi_cleanup_d3d_and_duplication(dxgi_ctx);
//         if(output) IDXGIOutput_Release(output);
//         if(adapter) IDXGIAdapter1_Release(adapter);
//         IDXGIFactory1_Release(factory);
//         return MINIAV_ERROR_SYSTEM_CALL_FAILED;
//     }
    
//     hr = IDXGIOutput1_DuplicateOutput(output1, (IUnknown*)dxgi_ctx->d3d_device, &dxgi_ctx->output_duplication);
//     if (FAILED(hr)) {
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: DuplicateOutput failed: 0x%X", hr);
//         dxgi_cleanup_d3d_and_duplication(dxgi_ctx);
//         // Release sequence
//         if(output1) IDXGIOutput1_Release(output1);
//         if(output) IDXGIOutput_Release(output);
//         if(adapter) IDXGIAdapter1_Release(adapter);
//         IDXGIFactory1_Release(factory);
//         return MINIAV_ERROR_SYSTEM_CALL_FAILED;
//     }
    
//     IDXGIOutput_GetDesc(output, &dxgi_ctx->output_desc);
//     dxgi_ctx->frame_width = dxgi_ctx->output_desc.DesktopCoordinates.right - dxgi_ctx->output_desc.DesktopCoordinates.left;
//     dxgi_ctx->frame_height = dxgi_ctx->output_desc.DesktopCoordinates.bottom - dxgi_ctx->output_desc.DesktopCoordinates.top;

//     // Create staging texture
//     D3D11_TEXTURE2D_DESC staging_desc;
//     ZeroMemory(&staging_desc, sizeof(staging_desc));
//     staging_desc.Width = dxgi_ctx->frame_width;
//     staging_desc.Height = dxgi_ctx->frame_height;
//     staging_desc.MipLevels = 1;
//     staging_desc.ArraySize = 1;
//     staging_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM; // Common desktop format
//     staging_desc.SampleDesc.Count = 1;
//     staging_desc.Usage = D3D11_USAGE_STAGING;
//     staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    
//     hr = ID3D11Device_CreateTexture2D(dxgi_ctx->d3d_device, &staging_desc, NULL, &dxgi_ctx->staging_texture);
//     if (FAILED(hr)) {
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to create staging texture: 0x%X", hr);
//         dxgi_cleanup_d3d_and_duplication(dxgi_ctx); // This will release output_duplication too
//         if(output1) IDXGIOutput1_Release(output1);
//         if(output) IDXGIOutput_Release(output);
//         if(adapter) IDXGIAdapter1_Release(adapter);
//         IDXGIFactory1_Release(factory);
//         return MINIAV_ERROR_SYSTEM_CALL_FAILED;
//     }


//     if(output1) IDXGIOutput1_Release(output1);
//     if(output) IDXGIOutput_Release(output);
//     if(adapter) IDXGIAdapter1_Release(adapter);
//     if(factory) IDXGIFactory1_Release(factory);

//     miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: D3D and Duplication initialized for Adapter%u Output%u.", adapter_idx, output_idx);
//     return MINIAV_SUCCESS;
// }

// static void dxgi_cleanup_d3d_and_duplication(DXGIScreenPlatformContext *dxgi_ctx) {
//     if (dxgi_ctx->output_duplication) {
//         IDXGIOutputDuplication_Release(dxgi_ctx->output_duplication);
//         dxgi_ctx->output_duplication = NULL;
//     }
//     if (dxgi_ctx->staging_texture) {
//         ID3D11Texture2D_Release(dxgi_ctx->staging_texture);
//         dxgi_ctx->staging_texture = NULL;
//     }
//     if (dxgi_ctx->d3d_context) {
//         ID3D11DeviceContext_Release(dxgi_ctx->d3d_context);
//         dxgi_ctx->d3d_context = NULL;
//     }
//     if (dxgi_ctx->d3d_device) {
//         ID3D11Device_Release(dxgi_ctx->d3d_device);
//         dxgi_ctx->d3d_device = NULL;
//     }
//     miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: D3D and Duplication resources cleaned up.");
// }


// static MiniAVResultCode dxgi_configure_display(MiniAVScreenContext *ctx, const char *display_id_utf8, const MiniAVVideoFormatInfo *format) {
//     if (!ctx || !ctx->platform_ctx || !display_id_utf8 || !format) return MINIAV_ERROR_INVALID_ARG;
//     DXGIScreenPlatformContext *dxgi_ctx = (DXGIScreenPlatformContext *)ctx->platform_ctx;

//     miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Configuring display ID: %s, Target FPS: %u/%u", 
//         display_id_utf8, format->frame_rate_numerator, format->frame_rate_denominator);

//     // Parse display_id_utf8 (e.g., "AdapterX_OutputY")
//     unsigned int adapter_idx = 0, output_idx = 0;
//     if (sscanf_s(display_id_utf8, "Adapter%u_Output%u", &adapter_idx, &output_idx) != 2) {
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Invalid display_id format: %s. Expected AdapterX_OutputY.", display_id_utf8);
//         return MINIAV_ERROR_INVALID_ARG;
//     }

//     EnterCriticalSection(&dxgi_ctx->critical_section);
//     if (dxgi_ctx->is_streaming) {
//         LeaveCriticalSection(&dxgi_ctx->critical_section);
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Cannot configure while streaming.");
//         return MINIAV_ERROR_ALREADY_RUNNING;
//     }

//     MiniAVResultCode res = dxgi_init_d3d_and_duplication(dxgi_ctx, adapter_idx, output_idx);
//     if (res != MINIAV_SUCCESS) {
//         LeaveCriticalSection(&dxgi_ctx->critical_section);
//         return res;
//     }
    
//     dxgi_ctx->adapter_index_internal = adapter_idx;
//     dxgi_ctx->output_index_internal = output_idx;
//     strncpy_s(dxgi_ctx->selected_device_id, MINIAV_DEVICE_ID_MAX_LEN, display_id_utf8, _TRUNCATE);


//     dxgi_ctx->configured_format = *format; // Store the requested format
//     if (format->frame_rate_denominator > 0 && format->frame_rate_numerator > 0) {
//         dxgi_ctx->target_fps = format->frame_rate_numerator / format->frame_rate_denominator;
//     } else {
//         dxgi_ctx->target_fps = 30; // Default FPS if not specified or invalid
//         miniav_log(MINIAV_LOG_LEVEL_WARN, "DXGI: Invalid target FPS in format, defaulting to %u FPS.", dxgi_ctx->target_fps);
//     }
//     if (dxgi_ctx->target_fps == 0) dxgi_ctx->target_fps = 1; // Ensure at least 1 FPS to avoid division by zero

//     // Actual width, height, and pixel format are determined by DXGI, stored during init_d3d_and_duplication
//     ctx->configured_format.width = dxgi_ctx->frame_width;
//     ctx->configured_format.height = dxgi_ctx->frame_height;
//     ctx->configured_format.pixel_format = dxgi_ctx->pixel_format; // Should be BGRA32
//     ctx->configured_format.frame_rate_numerator = dxgi_ctx->target_fps;
//     ctx->configured_format.frame_rate_denominator = 1;


//     LeaveCriticalSection(&dxgi_ctx->critical_section);
//     miniav_log(MINIAV_LOG_LEVEL_INFO, "DXGI: Configured for display %s. Actual resolution: %ux%u, Target FPS: %u.", 
//         display_id_utf8, dxgi_ctx->frame_width, dxgi_ctx->frame_height, dxgi_ctx->target_fps);
//     return MINIAV_SUCCESS;
// }

// static MiniAVResultCode dxgi_configure_window(MiniAVScreenContext *ctx, const char *window_id_utf8, const MiniAVVideoFormatInfo *format) {
//     MINIAV_UNUSED(ctx); MINIAV_UNUSED(window_id_utf8); MINIAV_UNUSED(format);
//     miniav_log(MINIAV_LOG_LEVEL_WARN, "DXGI: ConfigureWindow is not supported by DXGI backend.");
//     return MINIAV_ERROR_NOT_SUPPORTED;
// }

// static MiniAVResultCode dxgi_configure_region(MiniAVScreenContext *ctx, const char *display_id_utf8, int x, int y, int width, int height, const MiniAVVideoFormatInfo *format) {
//     MINIAV_UNUSED(ctx); MINIAV_UNUSED(display_id_utf8); MINIAV_UNUSED(x); MINIAV_UNUSED(y); MINIAV_UNUSED(width); MINIAV_UNUSED(height); MINIAV_UNUSED(format);
//     miniav_log(MINIAV_LOG_LEVEL_WARN, "DXGI: ConfigureRegion is not supported by DXGI backend (full display capture only).");
//     return MINIAV_ERROR_NOT_SUPPORTED;
// }

// static MiniAVResultCode dxgi_start_capture(MiniAVScreenContext *ctx, MiniAVBufferCallback callback, void *user_data) {
//     if (!ctx || !ctx->platform_ctx || !callback) return MINIAV_ERROR_INVALID_ARG;
//     DXGIScreenPlatformContext *dxgi_ctx = (DXGIScreenPlatformContext *)ctx->platform_ctx;

//     EnterCriticalSection(&dxgi_ctx->critical_section);
//     if (dxgi_ctx->is_streaming) {
//         LeaveCriticalSection(&dxgi_ctx->critical_section);
//         miniav_log(MINIAV_LOG_LEVEL_WARN, "DXGI: Capture already started.");
//         return MINIAV_ERROR_ALREADY_RUNNING;
//     }
//     if (!dxgi_ctx->output_duplication || !dxgi_ctx->staging_texture) {
//         LeaveCriticalSection(&dxgi_ctx->critical_section);
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Not configured. Call ConfigureDisplay first.");
//         return MINIAV_ERROR_NOT_INITIALIZED;
//     }

//     dxgi_ctx->app_callback_internal = callback;
//     dxgi_ctx->app_callback_user_data_internal = user_data;
//     dxgi_ctx->parent_ctx->app_callback = callback; // Also update parent
//     dxgi_ctx->parent_ctx->app_callback_user_data = user_data;

//     ResetEvent(dxgi_ctx->stop_event_handle); // Ensure stop event is not signaled
//     dxgi_ctx->is_streaming = TRUE;

//     dxgi_ctx->capture_thread_handle = CreateThread(NULL, 0, dxgi_capture_thread_proc, dxgi_ctx, 0, NULL);
//     if (dxgi_ctx->capture_thread_handle == NULL) {
//         dxgi_ctx->is_streaming = FALSE;
//         LeaveCriticalSection(&dxgi_ctx->critical_section);
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to create capture thread.");
//         return MINIAV_ERROR_SYSTEM_CALL_FAILED;
//     }

//     LeaveCriticalSection(&dxgi_ctx->critical_section);
//     miniav_log(MINIAV_LOG_LEVEL_INFO, "DXGI: Capture started.");
//     return MINIAV_SUCCESS;
// }

// static MiniAVResultCode dxgi_stop_capture(MiniAVScreenContext *ctx) {
//     if (!ctx || !ctx->platform_ctx) return MINIAV_ERROR_NOT_INITIALIZED;
//     DXGIScreenPlatformContext *dxgi_ctx = (DXGIScreenPlatformContext *)ctx->platform_ctx;

//     EnterCriticalSection(&dxgi_ctx->critical_section);
//     if (!dxgi_ctx->is_streaming) {
//         LeaveCriticalSection(&dxgi_ctx->critical_section);
//         miniav_log(MINIAV_LOG_LEVEL_WARN, "DXGI: Capture not started or already stopped.");
//         return MINIAV_SUCCESS; // Or MINIAV_ERROR_INVALID_OPERATION
//     }

//     miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Stopping capture.");
//     SetEvent(dxgi_ctx->stop_event_handle);
//     dxgi_ctx->is_streaming = FALSE; // Set flag early
//     LeaveCriticalSection(&dxgi_ctx->critical_section); // Release lock before waiting

//     if (dxgi_ctx->capture_thread_handle) {
//         miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Waiting for capture thread to exit...");
//         WaitForSingleObject(dxgi_ctx->capture_thread_handle, INFINITE);
//         CloseHandle(dxgi_ctx->capture_thread_handle);
//         dxgi_ctx->capture_thread_handle = NULL;
//         miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Capture thread exited.");
//     }
    
//     // Re-acquire lock if further cleanup needs it, but for now, just log.
//     miniav_log(MINIAV_LOG_LEVEL_INFO, "DXGI: Capture stopped.");
//     return MINIAV_SUCCESS;
// }

// static MiniAVResultCode dxgi_release_buffer(MiniAVScreenContext *ctx, void *native_buffer_payload_resource_ptr) {
//     MINIAV_UNUSED(ctx); // Context might be useful for logging or D3D device access if not in payload
//     if (!native_buffer_payload_resource_ptr) {
//         miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: native_buffer_payload_resource_ptr is NULL in release_buffer.");
//         return MINIAV_ERROR_INVALID_ARG;
//     }

//     DXGIFrameReleasePayload *frame_payload = (DXGIFrameReleasePayload *)native_buffer_payload_resource_ptr;

//     if (frame_payload->d3d_context_for_unmap && frame_payload->staging_texture_for_frame) {
//         ID3D11DeviceContext_Unmap(frame_payload->d3d_context_for_unmap,
//                                   (ID3D11Resource*)frame_payload->staging_texture_for_frame,
//                                   frame_payload->subresource_for_unmap);
//         miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Unmapped staging texture for frame.");
//     } else {
//         miniav_log(MINIAV_LOG_LEVEL_WARN, "DXGI: Could not unmap, context or texture missing in payload.");
//     }

//     if (frame_payload->staging_texture_for_frame) {
//         ULONG ref_count = ID3D11Texture2D_Release(frame_payload->staging_texture_for_frame);
//         miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Released per-frame staging texture. Ref count after release: %lu", ref_count);
//     }
    
//     // The DXGIFrameReleasePayload struct itself was allocated by miniav_calloc
//     miniav_free(frame_payload); 
//     miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Freed DXGIFrameReleasePayload.");

//     return MINIAV_SUCCESS;
// }


// static DWORD WINAPI dxgi_capture_thread_proc(LPVOID param) {
//     DXGIScreenPlatformContext *dxgi_ctx = (DXGIScreenPlatformContext *)param;
//     if (!dxgi_ctx) return 1;

//     HRESULT hr;
//     IDXGIResource* desktop_resource = NULL;
//     DXGI_OUTDUPL_FRAME_INFO frame_info;
//     ID3D11Texture2D* acquired_texture = NULL; // Texture from AcquireNextFrame

//     UINT frame_timeout_ms = 1000 / dxgi_ctx->target_fps;
//     if (frame_timeout_ms == 0) frame_timeout_ms = 16; // Cap at ~60fps if target_fps is too high or 0

//     miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Capture thread started. Target FPS: %u, Frame Timeout: %u ms.", dxgi_ctx->target_fps, frame_timeout_ms);

//     while (dxgi_ctx->is_streaming) {
//         if (WaitForSingleObject(dxgi_ctx->stop_event_handle, 0) == WAIT_OBJECT_0) {
//             miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Stop event signaled in capture thread.");
//             break;
//         }

//         // Release previous frame's acquired_texture if any (should be released by DuplicateOutput implicitly on next acquire or explicit ReleaseFrame)
//         if (acquired_texture) {
//             ID3D11Texture2D_Release(acquired_texture);
//             acquired_texture = NULL;
//         }
//         if (dxgi_ctx->output_duplication) { // Check if duplication is still valid
//              IDXGIOutputDuplication_ReleaseFrame(dxgi_ctx->output_duplication); // Release any held frame before acquiring next
//         }


//         hr = IDXGIOutputDuplication_AcquireNextFrame(dxgi_ctx->output_duplication, 500, &frame_info, &desktop_resource);

//         if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
//             // miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: AcquireNextFrame timeout.");
//             Sleep(1); // Small sleep on timeout
//             continue;
//         }
//         if (hr == DXGI_ERROR_ACCESS_LOST) {
//             miniav_log(MINIAV_LOG_LEVEL_WARN, "DXGI: Desktop Duplication access lost. Attempting to reinitialize.");
//             // Need to re-initialize duplication. This is complex and involves releasing and recreating resources.
//             // For simplicity here, we'll stop streaming. A robust implementation would re-try.
//             EnterCriticalSection(&dxgi_ctx->critical_section);
//             dxgi_cleanup_d3d_and_duplication(dxgi_ctx); // Clean up old D3D resources
//             MiniAVResultCode reinit_res = dxgi_init_d3d_and_duplication(dxgi_ctx, dxgi_ctx->adapter_index_internal, dxgi_ctx->output_index_internal);
//             if (reinit_res != MINIAV_SUCCESS) {
//                  miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to reinitialize duplication after access lost. Stopping stream.");
//                  dxgi_ctx->is_streaming = FALSE; // Stop the loop
//             }
//             LeaveCriticalSection(&dxgi_ctx->critical_section);
//             if (!dxgi_ctx->is_streaming) break;
//             continue;
//         }
//         if (FAILED(hr) || !desktop_resource) {
//             miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: AcquireNextFrame failed with HRESULT: 0x%X", hr);
//             Sleep(frame_timeout_ms); // Wait before retrying or exiting
//             // Potentially stop streaming after several consecutive errors
//             continue;
//         }

//         if (frame_info.LastPresentTime.QuadPart == 0) { // No update
//              if(desktop_resource) IDXGIResource_Release(desktop_resource);
//              desktop_resource = NULL;
//              // IDXGIOutputDuplication_ReleaseFrame(dxgi_ctx->output_duplication); // Already called above
//              Sleep(1);
//              continue;
//         }


//         hr = IDXGIResource_QueryInterface(desktop_resource, &IID_ID3D11Texture2D, (void**)&acquired_texture);
//         IDXGIResource_Release(desktop_resource); // Release the IDXGIResource interface
//         desktop_resource = NULL;

//         if (FAILED(hr) || !acquired_texture) {
//             miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to query ID3D11Texture2D from desktop resource: 0x%X", hr);
//             continue;
//         }

//         // Copy to staging texture
//         ID3D11DeviceContext_CopyResource(dxgi_ctx->d3d_context, (ID3D11Resource*)dxgi_ctx->staging_texture, (ID3D11Resource*)acquired_texture);

//         D3D11_MAPPED_SUBRESOURCE mapped_rect;
//         hr = ID3D11DeviceContext_Map(dxgi_ctx->d3d_context, (ID3D11Resource*)dxgi_ctx->staging_texture, 0, D3D11_MAP_READ, 0, &mapped_rect);
//         if (FAILED(hr)) {
//             miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to map staging texture: 0x%X", hr);
//             // acquired_texture is released at the start of the loop or on exit
//             continue;
//         }

//         MiniAVBuffer buffer;
//         memset(&buffer, 0, sizeof(MiniAVBuffer));
//         buffer.type = MINIAV_BUFFER_TYPE_VIDEO;
        
//         // Convert QPC time to microseconds
//         buffer.timestamp_us = miniav_qpc_to_microseconds(frame_info.LastPresentTime, dxgi_ctx->qpc_frequency);

//         buffer.data.video.width = dxgi_ctx->frame_width;
//         buffer.data.video.height = dxgi_ctx->frame_height;
//         buffer.data.video.pixel_format = dxgi_ctx->pixel_format; // BGRA32
//         buffer.data.video.planes[0] = mapped_rect.pData;
//         buffer.data.video.stride_bytes[0] = mapped_rect.RowPitch;
//         buffer.data_size_bytes = mapped_rect.RowPitch * dxgi_ctx->frame_height; // Approximate, actual content might be less for partial updates
//         buffer.user_data = dxgi_ctx->app_callback_user_data_internal;

//         // Prepare payload for release
//         // For DXGI, we map the staging_texture. The release operation needs to unmap it.
//         // We don't create a new staging texture per frame to avoid overhead,
//         // but this means the user *must* be done with the data from mapped_rect.pData
//         // *before* the next frame is mapped, or they need to copy it.
//         // The current design with MiniAV_ReleaseBuffer implies the buffer is usable until released.
//         // So, we MUST provide a unique resource or a way to manage the single staging_texture.
//         // Let's create a copy of the staging texture for each frame to be safe with the explicit release model.
        
//         ID3D11Texture2D* per_frame_staging_texture = NULL;
//         D3D11_TEXTURE2D_DESC per_frame_desc;
//         ID3D11Texture2D_GetDesc(dxgi_ctx->staging_texture, &per_frame_desc); // Get desc from the main staging texture
//         // Ensure it's a staging texture desc
//         per_frame_desc.Usage = D3D11_USAGE_STAGING;
//         per_frame_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
//         per_frame_desc.BindFlags = 0;
//         per_frame_desc.MiscFlags = 0;

//         hr = ID3D11Device_CreateTexture2D(dxgi_ctx->d3d_device, &per_frame_desc, NULL, &per_frame_staging_texture);
//         if (FAILED(hr) || !per_frame_staging_texture) {
//             miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to create per-frame staging texture: 0x%X", hr);
//             ID3D11DeviceContext_Unmap(dxgi_ctx->d3d_context, (ID3D11Resource*)dxgi_ctx->staging_texture, 0);
//             // acquired_texture is released at the start of the loop
//             continue;
//         }
//         // Copy from the main staging (already containing current frame) to the per-frame one
//         ID3D11DeviceContext_CopyResource(dxgi_ctx->d3d_context, (ID3D11Resource*)per_frame_staging_texture, (ID3D11Resource*)dxgi_ctx->staging_texture);
        
//         // Now unmap the main staging texture, as its content is copied
//         ID3D11DeviceContext_Unmap(dxgi_ctx->d3d_context, (ID3D11Resource*)dxgi_ctx->staging_texture, 0);

//         // Map the new per-frame staging texture
//         D3D11_MAPPED_SUBRESOURCE per_frame_mapped_rect;
//         hr = ID3D11DeviceContext_Map(dxgi_ctx->d3d_context, (ID3D11Resource*)per_frame_staging_texture, 0, D3D11_MAP_READ, 0, &per_frame_mapped_rect);
//         if (FAILED(hr)) {
//             miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to map per-frame staging texture: 0x%X", hr);
//             ID3D11Texture2D_Release(per_frame_staging_texture);
//             // acquired_texture is released at the start of the loop
//             continue;
//         }
//         buffer.data.video.planes[0] = per_frame_mapped_rect.pData; // Update pointer
//         buffer.data.video.stride_bytes[0] = per_frame_mapped_rect.RowPitch; // Update stride
//         buffer.data_size_bytes = per_frame_mapped_rect.RowPitch * dxgi_ctx->frame_height;


//         MiniAVNativeBufferInternalPayload *payload = (MiniAVNativeBufferInternalPayload *)miniav_calloc(1, sizeof(MiniAVNativeBufferInternalPayload));
//         DXGIFrameReleasePayload *frame_release_payload = (DXGIFrameReleasePayload *)miniav_calloc(1, sizeof(DXGIFrameReleasePayload));

//         if (!payload || !frame_release_payload) {
//             miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to allocate payload for buffer release.");
//             ID3D11DeviceContext_Unmap(dxgi_ctx->d3d_context, (ID3D11Resource*)per_frame_staging_texture, 0);
//             ID3D11Texture2D_Release(per_frame_staging_texture);
//             miniav_free(payload); // one might be non-null
//             miniav_free(frame_release_payload);
//             // acquired_texture is released at the start of the loop
//             continue;
//         }

//         frame_release_payload->staging_texture_for_frame = per_frame_staging_texture; // Already AddRef'd by CreateTexture2D
//         frame_release_payload->d3d_context_for_unmap = dxgi_ctx->d3d_context; // Not AddRef'd per frame
//         frame_release_payload->subresource_for_unmap = 0;

//         payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_VIDEO_SCREEN; // Generic screen type, or make DXGI specific
//         payload->context_owner = dxgi_ctx->parent_ctx; // Pointer to MiniAVScreenContext
//         payload->native_resource_ptr = frame_release_payload;
//         buffer.internal_handle = payload;

//         if (dxgi_ctx->app_callback_internal) {
//             dxgi_ctx->app_callback_internal(&buffer, dxgi_ctx->app_callback_user_data_internal);
//         } else {
//             // If no app callback, we must release the resources we prepared for it
//             miniav_log(MINIAV_LOG_LEVEL_WARN, "DXGI: No app callback set, releasing frame internally.");
//             ID3D11DeviceContext_Unmap(dxgi_ctx->d3d_context, (ID3D11Resource*)per_frame_staging_texture, 0);
//             ID3D11Texture2D_Release(per_frame_staging_texture);
//             miniav_free(frame_release_payload);
//             miniav_free(payload);
//         }
        
//         // acquired_texture (original GPU texture from duplication) is released at the start of the next loop iteration or on thread exit.
//         // The per_frame_staging_texture is now owned by the DXGIFrameReleasePayload and will be released by dxgi_release_buffer.

//         // Frame processing done for this iteration
//         DWORD sleep_duration_ms = frame_timeout_ms; // Base sleep on target FPS
//         // More sophisticated frame pacing could be added here.
//         Sleep(sleep_duration_ms > 0 ? sleep_duration_ms : 1);
//     }

//     if (acquired_texture) { // Clean up last acquired texture if loop exited
//         ID3D11Texture2D_Release(acquired_texture);
//         acquired_texture = NULL;
//     }
//     if (dxgi_ctx->output_duplication) { // Release any final held frame
//          IDXGIOutputDuplication_ReleaseFrame(dxgi_ctx->output_duplication);
//     }


//     miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Capture thread finished.");
//     return 0;
// }


// // Define the actual ops struct for DXGI Screen Capture
// const ScreenContextInternalOps g_screen_ops_win_dxgi = {
//     .init_platform = dxgi_init_platform,
//     .destroy_platform = dxgi_destroy_platform,
//     .enumerate_displays = dxgi_enumerate_displays,
//     .enumerate_windows = dxgi_enumerate_windows, // Not supported
//     .configure_display = dxgi_configure_display,
//     .configure_window = dxgi_configure_window,   // Not supported
//     .configure_region = dxgi_configure_region,   // Not supported
//     .start_capture = dxgi_start_capture,
//     .stop_capture = dxgi_stop_capture,
//     .release_buffer = dxgi_release_buffer
// };

// MiniAVResultCode miniav_screen_context_platform_init_windows_dxgi(MiniAVScreenContext *ctx) {
//     if (!ctx) return MINIAV_ERROR_INVALID_ARG;
//     ctx->ops = &g_screen_ops_win_dxgi;
//     miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Assigned Windows DXGI screen ops.");
//     // The caller (e.g., MiniAV_Screen_CreateContext) will call ctx->ops->init_platform()
//     return MINIAV_SUCCESS;
// }