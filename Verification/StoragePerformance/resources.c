#include <libproc.h>
#include <mach/mach_time.h>
#include <unistd.h>
#include <stdint.h>
uint64_t storage_written(void) { struct rusage_info_v2 r={0}; proc_pid_rusage(getpid(),RUSAGE_INFO_V2,(rusage_info_t*)&r); return r.ri_diskio_byteswritten; }
double storage_cpu(void) { struct rusage_info_v2 r={0}; mach_timebase_info_data_t tb; mach_timebase_info(&tb); proc_pid_rusage(getpid(),RUSAGE_INFO_V2,(rusage_info_t*)&r); return (double)(r.ri_user_time+r.ri_system_time)*tb.numer/tb.denom/1e9; }
