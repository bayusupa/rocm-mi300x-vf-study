# Detailed Findings: AMD MI300X VF on AMD Developer Cloud

## Environment

- **Platform:** AMD Developer Cloud (`devcloud.amd.com`)
- **Instance type:** ROCm 7.2 on Ubuntu 24.04 (1-Click Droplet via DigitalOcean)
- **GPU:** AMD Instinct MI300X VF (Virtual Function via SR-IOV)
- **ROCm Driver:** 6.16.13
- **Observation period:** ~72 hours continuous workload
- **Workload:** Compute-intensive GPU application (single process, 5 threads)

---

## Finding 1 — Clock Frequencies Locked Below Maximum

Under sustained 100% GPU load, all clock domains remained at the **lowest available frequency level**, not scaling to maximum despite full utilization.

| Clock Domain | Observed | Maximum Available | Utilization |
|--------------|----------|------------------|-------------|
| sclk (shader) | 1259 MHz | 2100 MHz | 59.9% |
| mclk (memory) | 900 MHz | 1300 MHz | 69.2% |
| fclk (fabric) | 1300 MHz | 1800 MHz | 72.2% |
| socclk | 41 MHz | 1143 MHz | 3.6% |

**Hypothesis:** SR-IOV Virtual Function restricts clock governor access. The `Performance Level: auto` setting cannot escalate clocks because the hypervisor layer (AMD DevCloud infrastructure) controls physical clock domains and does not expose them to the VF guest. Manual clock override via `rocm-smi --setsclk` is expected to fail or be silently ignored in this environment.

**Impact:** If sclk and mclk were to reach maximum, compute throughput could theoretically increase by ~40–70% depending on workload memory access patterns.

---

## Finding 2 — VRAM Severely Underutilized

Despite 192GB HBM3 being available, the workload allocated only ~5.87 GB (~2%).

| Metric | Value |
|--------|-------|
| VRAM Total | 205,822,885,888 bytes (192 GB) |
| VRAM Used | 6,165,929,984 bytes (5.87 GB) |
| Utilization | **~2%** |
| Memory R/W Activity | 4% |

The MI300X unified memory architecture is specifically designed for large-model workloads that saturate HBM3 bandwidth. A workload utilizing only 2% of VRAM is unlikely to benefit from the memory subsystem's full bandwidth, which is theoretically ~5.3 TB/s on the physical MI300X.

**Observation:** SDMA (System DMA) usage was reported as `0`, suggesting data movement between host and device memory was minimal or non-existent during observation.

---

## Finding 3 — CU Occupancy Reported as Zero

KFD process table shows `CU OCCUPANCY: 0` despite GPU use being 100%.

```
PID     PROCESS NAME    GPU(s)  VRAM USED       SDMA USED    CU OCCUPANCY
8280    alpha-bin       1       5865951232      0             0
```

**Hypothesis:** CU Occupancy metric may not be supported or correctly reported on VF instances. The GPU use percentage (100%) and power draw (749W / 750W cap) confirm the device is under heavy load, contradicting a true CU occupancy of zero. This may be a monitoring limitation specific to SR-IOV VF environments rather than a reflection of actual compute utilization.

**Recommendation for AMD/ROCm devs:** Validate CU Occupancy reporting via KFD on VF instances. If the metric is unsupported, returning `0` without a warning could mislead performance analysis.

---

## Finding 4 — Thermal Behavior

| Sensor | Temperature |
|--------|-------------|
| Junction (GPU core) | 89°C |
| Memory (HBM3) | 50°C |

Junction temperature at 89°C is within operational range but approaching the thermal throttle threshold (typically ~95°C for MI300X). Memory temperature at 50°C is well within safe range.

**Notable:** Despite running at 749W / 750W power cap for ~72 hours continuously, no thermal throttling events were observed in process metrics (no significant performance degradation over time). This suggests AMD DevCloud's cooling infrastructure is adequate for sustained full-load operation.

---

## Finding 5 — Process Threading vs Available Cores

The workload process utilized only **5 threads** despite 20 vCPU cores being available.

```
Threads:              5
Cpus_allowed_list:    0-19  (all 20 cores available)
```

For workloads that could benefit from CPU-side preprocessing or dispatch management, there is significant headroom in CPU utilization that is currently unused.

---

## Finding 6 — Compute Partition: SPX

The GPU was operating in **SPX (Single Partition eXclusive)** mode with **NPS1** memory partition.

SPX mode means the entire GCD (Graphics Compute Die) is treated as a single compute resource. For the MI300X which contains multiple GCDs, SPX on a VF likely means access to one logical GCD partition rather than all physical compute resources on the full MI300X.

**Implication:** The physical MI300X has 304 Compute Units across multiple GCDs. In VF/SPX mode, the accessible CUs may be a subset of the full hardware. This could partially explain the clock and throughput limitations observed.

---

## Summary Table

| Finding | Severity | Likely Cause | Actionable? |
|---------|----------|--------------|-------------|
| sclk at 59.9% of max | High | SR-IOV VF clock restriction | No (infrastructure limitation) |
| mclk at 69.2% of max | High | SR-IOV VF clock restriction | No (infrastructure limitation) |
| VRAM at 2% utilization | Medium | Workload design | Yes (application-side) |
| CU Occupancy = 0 | Unknown | Metric not supported on VF | Needs AMD/ROCm investigation |
| 5 threads / 20 cores | Low | Workload design | Yes (application-side) |
| SPX partition mode | Informational | VF allocation policy | No (infrastructure) |

---

## Reproducibility

To reproduce these observations on AMD Developer Cloud:

1. Provision a ROCm 7.2 / Ubuntu 24.04 droplet with MI300X GPU
2. Run any sustained GPU compute workload (e.g., HIP GEMM, rocBLAS benchmark)
3. Collect: `rocm-smi --showallinfo`, `rocm-smi --showmeminfo vram`, `cat /proc/<pid>/status`, `lscpu`
4. Compare clock frequencies against `rocm-smi --showclkrange`

Raw data from this study is available in the `/data` directory.
