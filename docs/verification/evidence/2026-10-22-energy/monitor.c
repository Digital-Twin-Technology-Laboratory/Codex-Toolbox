#include <libproc.h>
#include <sys/resource.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <mach/mach_time.h>
int main(int argc, char **argv) {
 if (argc != 3) return 2;
 int pid=atoi(argv[1]), seconds=atoi(argv[2]);
 mach_timebase_info_data_t tb; mach_timebase_info(&tb); double scale=(double)tb.numer/tb.denom;
 struct rusage_info_v2 first={0}, prev={0}, cur={0};
 if(proc_pid_rusage(pid,RUSAGE_INFO_V2,(rusage_info_t*)&first)) {perror("proc_pid_rusage");return 1;}
 prev=first;
 printf("pid=%d duration=%d; elapsed,cpu_ms,write_MiB,read_MiB,idle_wakeups,interrupt_wakeups\n",pid,seconds);fflush(stdout);
 for(int t=1;t<=seconds;t++) {
  sleep(1);
  if(proc_pid_rusage(pid,RUSAGE_INFO_V2,(rusage_info_t*)&cur)) return 1;
  double cpu=(double)(cur.ri_user_time+cur.ri_system_time-prev.ri_user_time-prev.ri_system_time)*scale/1e6;
  double wr=(double)(cur.ri_diskio_byteswritten-prev.ri_diskio_byteswritten)/1048576.;
  if(cpu>50 || wr>1 || t%15==0) {printf("%d,%.2f,%.3f,%.3f,%llu,%llu\n",t,cpu,wr,(double)(cur.ri_diskio_bytesread-prev.ri_diskio_bytesread)/1048576.,cur.ri_pkg_idle_wkups-prev.ri_pkg_idle_wkups,cur.ri_interrupt_wkups-prev.ri_interrupt_wkups);fflush(stdout);}
  prev=cur;
 }
 printf("total_cpu_s=%.3f total_write_MiB=%.3f total_read_MiB=%.3f total_idle_wakeups=%llu total_interrupt_wakeups=%llu\n",(double)(cur.ri_user_time+cur.ri_system_time-first.ri_user_time-first.ri_system_time)*scale/1e9,(double)(cur.ri_diskio_byteswritten-first.ri_diskio_byteswritten)/1048576.,(double)(cur.ri_diskio_bytesread-first.ri_diskio_bytesread)/1048576.,cur.ri_pkg_idle_wkups-first.ri_pkg_idle_wkups,cur.ri_interrupt_wkups-first.ri_interrupt_wkups);
}
