#ifndef gahpc_Bridging_Header_h
#define gahpc_Bridging_Header_h

// Rust C FFI — AHP proxy static library
extern int ahpc_start(const char *config_json);
extern int ahpc_stop(void);
extern int ahpc_status(void);

#endif
