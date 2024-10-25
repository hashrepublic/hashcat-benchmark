# Hashcat Benchmark

## Overview

**Hashcat Benchmark** is a project aimed at providing real-world benchmarking results of Hashcat's performance in various environments. Unlike traditional benchmarks conducted in optimized settings, this project focuses on capturing how Hashcat performs under actual usage conditions.


## How it works

- Based on hashcat hash sample
- Retrieve max length of payload (it depends if running with `-O`)
- Start hashcat with a huge mask at maximum length
- Let it run for a determined time (60 seconds by default)
- Get hashcat status and speed
- Stop hashcat 

## Usage

It's all developped unded bash to maximise compatibility accross environment (including GPU rental solutions).   
Be carefull as running a full benchmark can take up to a day. But you'll have accurate results.  
```bash
git clone https://github.com/yourusername/hashcat-benchmark.git
cd hashcat-benchmark
# Run benchmark for mode 3200
bash benchmark.sh 3200 
# Run benchmark for mode 3200 (optimized)
bash benchmark.sh -O 3200 
# Run benchmark for all modes
bash benchmark.sh ALL
# Run benchmark for all modes (optimized)
bash benchmark.sh -O ALL
```
