# Resource Measurements

Resource requests were tested on Explorer using the same sample, NA12878, through the per-sample pipeline (stages 0-5).

| CPUs | Requested memory | Wall time | CPU utilized | CPU efficiency | MaxRSS |
|---:|---:|---:|---:|---:|---:|
| 2 | 24G | 00:12:08 | 00:19:12 | 79.12% | 6.85 GB |
| 4 | 8G | 00:09:57 | 00:21:57 | 55.15% | 16.20 GB |
| 8 | 24G | 00:08:06 | 00:24:17 | 37.47% | 17.22 GB |

Increasing the allocation from 2 to 4 CPUs reduced the wall time from 12:08 to
9:57. Increasing it again to 8 CPUs reduced the wall time to 8:06, but CPU
efficiency fell to 37.47%. I therefore selected 4 CPUs per task as a compromise
between elapsed time and efficient use of allocated cores.

The largest observed MaxRSS was 17.22 GB, so I increased the memory request from
the initial 8G to 24G to leave headroom above the measured peak. The time limit
remains 02:00:00, which is well above the measured per-sample runtimes.
