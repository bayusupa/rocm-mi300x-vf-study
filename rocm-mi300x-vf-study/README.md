# rocm-mi300x-vf-study

A community observation study of AMD Instinct MI300X behavior in a **Virtual Function (VF)** environment on AMD Developer Cloud.

This repository documents GPU behavior, clock frequency patterns, memory utilization, and thermal characteristics of the MI300X when accessed via SR-IOV VF — as opposed to bare-metal or full-device access.

The goal is to provide reproducible data that may be useful for:
- AMD and ROCm developers investigating VF performance characteristics
- Researchers benchmarking MI300X in cloud environments
- Developers building HPC or AI workloads on AMD Developer Cloud

---

## Key Observations

### Clock Frequencies Under Full Load

Under sustained 100% GPU utilization, all clock domains remained at the **lowest available frequency** and did not scale up despite full load:

| Clock | Observed | Max Available | % of Max |
|-------|----------|---------------|----------|
| sclk (shader) | 1259 MHz | 2100 MHz | **59.9%** |
| mclk (memory) | 900 MHz | 1300 MHz | **69.2%** |
| fclk (fabric) | 1300 MHz | 1800 MHz | **72.2%** |
| socclk | 41 MHz | 1143 MHz | **3.6%** |

The performance level was set to `auto`. Manual clock override via `rocm-smi` is expected to be restricted in VF environments due to SR-IOV hypervisor control.

### VRAM Utilization

Despite 192GB HBM3 being available, the observed workload allocated only ~2% of total VRAM:

```
VRAM Total : 192 GB (205,822,885,888 bytes)
VRAM Used  : ~5.87 GB (6,165,929,984 bytes)
Utilization: ~2%
Memory R/W : 4%
SDMA Used  : 0
```

### CU Occupancy Reporting

KFD process table reported `CU OCCUPANCY: 0` despite GPU utilization being at 100% and power draw at 749W / 750W cap. This may indicate a monitoring limitation specific to VF instances rather than actual zero occupancy.

### Thermal Behavior

| Sensor | Temperature |
|--------|-------------|
| Junction | 89°C |
| HBM3 Memory | 50°C |

No thermal throttling observed over ~72 hours of continuous full-load operation.

---

## Environment

| Component | Details |
|-----------|---------|
| Platform | AMD Developer Cloud (devcloud.amd.com) |
| Instance | ROCm 7.2 on Ubuntu 24.04 (DigitalOcean 1-Click) |
| GPU | AMD Instinct MI300X VF (GFX942) |
| ROCm Driver | 6.16.13 |
| Compute Partition | SPX |
| Memory Partition | NPS1 |
| Host CPU | Intel Xeon Platinum 8568Y+ (20 vCPU, KVM) |
| Observation Period | ~72 hours continuous |

---

## Repository Structure

```
rocm-mi300x-vf-study/
├── README.md               ← this file
├── data/
│   ├── rocm-smi-full.txt   ← full rocm-smi --showallinfo output
│   ├── process-status.txt  ← /proc/<pid>/status + notes
│   └── lscpu.txt           ← host CPU info
├── analysis/
│   └── findings.md         ← detailed findings per observation
└── scripts/
    └── monitor.sh          ← real-time monitoring script
```

---

## How to Reproduce

1. Provision a ROCm 7.2 / Ubuntu 24.04 instance on AMD Developer Cloud
2. Run a sustained GPU compute workload (e.g., rocBLAS GEMM, HIP benchmark)
3. Collect data:

```bash
# GPU full info
rocm-smi --showallinfo > data/rocm-smi-full.txt

# VRAM usage
rocm-smi --showmeminfo vram >> data/rocm-smi-full.txt

# Process info (replace <pid> with your workload PID)
cat /proc/<pid>/status > data/process-status.txt

# Host CPU
lscpu > data/lscpu.txt
```

4. Run the monitor script during workload:

```bash
bash scripts/monitor.sh 10   # collect every 10 seconds
```

---

## Open Questions

These findings raise several questions that may warrant further investigation:

1. **Is clock scaling intentionally disabled on VF instances?** If so, is this documented anywhere in AMD DevCloud or ROCm documentation?

2. **Is CU Occupancy reporting expected to return 0 on VF?** If yes, should the metric surface a warning rather than a misleading zero?

3. **What is the actual CU count accessible in SPX/VF mode?** The physical MI300X has 304 CUs across multiple GCDs — how many are exposed in a single VF allocation?

4. **Can mclk be increased via ROCm on VF?** `rocm-smi --setmclk` — does it apply, fail silently, or return an error?

5. **Does SDMA being unused affect HBM3 bandwidth?** With SDMA = 0, what is the actual memory bandwidth path for compute workloads on VF?

---

## Contributing

If you have access to AMD Developer Cloud or other MI300X VF environments, contributions are welcome:

- Additional `rocm-smi` snapshots from different workloads
- Results from attempting manual clock override (`rocm-smi --setsclk`, `--setmclk`)
- Comparison data from bare-metal or full-device MI300X access
- Data from different ROCm versions or driver releases

Please open an issue or pull request.

---

## Related Resources

- [AMD ROCm Documentation](https://rocm.docs.amd.com/)
- [AMD Instinct MI300X Product Page](https://www.amd.com/en/products/accelerators/instinct/mi300/mi300x.html)
- [ROCm GitHub](https://github.com/ROCm/ROCm)
- [AMD Developer Cloud](https://www.amd.com/en/developer/resources/cloud-computing.html)

---

*Data collected June 2026 on AMD Developer Cloud. All observations are from a VF (Virtual Function) instance and may not reflect bare-metal MI300X behavior.*
