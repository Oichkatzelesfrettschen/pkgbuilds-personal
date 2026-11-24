#!/usr/bin/env bash
# ============================================================================
# EIRIKR BASH CONFIGURATION - CUDA ENVIRONMENT
# ============================================================================
# Part of eirikr-bash-config package
# CUDA configuration for NVIDIA RTX 4070 (Ada Lovelace, Compute Capability 8.9)
# ============================================================================

# NOTE: This can be disabled if you don't have an NVIDIA GPU or don't use CUDA
# To disable: Comment out the source line in your ~/.bashrc

# CUDA base paths
export CUDA_HOME=/opt/cuda
export PATH=$PATH:/opt/cuda/bin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/cuda/lib64

# RTX 4070 specific (Compute Capability 8.9)
export TORCH_CUDA_ARCH_LIST="8.9"
export CUDA_ARCHITECTURES="89"

# CUDA architecture settings
export CUDAARCHS="89"
export CUDA_ARCH_BIN="8.9"
export CUDA_ARCH_PTX="8.9"

# NVCC compiler default flags
export CUDAFLAGS="-O3 -use_fast_math -Xptxas=-v -gencode=arch=compute_89,code=sm_89 -gencode=arch=compute_89,code=compute_89"

# CMake CUDA integration
export CMAKE_CUDA_ARCHITECTURES="89"
export CMAKE_CUDA_FLAGS="-O3 -use_fast_math"

# PyTorch JIT compilation
export TORCH_NVCC_FLAGS="-Xfatbin -compress-all"

# ============================================================================
# END OF CUDA CONFIGURATION
# ============================================================================
