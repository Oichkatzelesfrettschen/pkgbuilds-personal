// Sustained pinned H2D bandwidth: the ceiling on any streamed-weight decode rate.
#include <cstdio>
#include <cuda_runtime.h>

#define CK(x) do{ cudaError_t e=(x); if(e){ printf("ERR %s @%d\n", cudaGetErrorString(e), __LINE__); return 1; } }while(0)

int main(int argc, char** argv){
    size_t mb = (argc>1)? atol(argv[1]) : 1024;
    int iters = (argc>2)? atoi(argv[2]) : 20;
    size_t bytes = mb*1024ull*1024ull;
    void *h=nullptr,*d=nullptr;
    CK(cudaHostAlloc(&h,bytes,cudaHostAllocDefault));
    CK(cudaMalloc(&d,bytes));
    memset(h,0x5a,bytes);
    cudaStream_t s; CK(cudaStreamCreate(&s));
    cudaEvent_t a,b; CK(cudaEventCreate(&a)); CK(cudaEventCreate(&b));
    // warmup
    for(int i=0;i<3;i++) CK(cudaMemcpyAsync(d,h,bytes,cudaMemcpyHostToDevice,s));
    CK(cudaStreamSynchronize(s));
    CK(cudaEventRecord(a,s));
    for(int i=0;i<iters;i++) CK(cudaMemcpyAsync(d,h,bytes,cudaMemcpyHostToDevice,s));
    CK(cudaEventRecord(b,s));
    CK(cudaStreamSynchronize(s));
    float ms=0; CK(cudaEventElapsedTime(&ms,a,b));
    double gib = (double)bytes*iters/(1024.0*1024.0*1024.0);
    printf("H2D pinned: %.2f GiB in %.2f ms = %.2f GiB/s  (buf=%zu MiB, iters=%d)\n",
           gib, ms, gib/(ms/1000.0), mb, iters);
    // D2H for symmetry
    CK(cudaEventRecord(a,s));
    for(int i=0;i<iters;i++) CK(cudaMemcpyAsync(h,d,bytes,cudaMemcpyDeviceToHost,s));
    CK(cudaEventRecord(b,s));
    CK(cudaStreamSynchronize(s));
    CK(cudaEventElapsedTime(&ms,a,b));
    printf("D2H pinned: %.2f GiB/s\n", gib/(ms/1000.0));
    // pageable H2D for contrast
    void* hp = malloc(bytes); memset(hp,0x5a,bytes);
    CK(cudaEventRecord(a,s));
    for(int i=0;i<iters;i++) CK(cudaMemcpyAsync(d,hp,bytes,cudaMemcpyHostToDevice,s));
    CK(cudaEventRecord(b,s));
    CK(cudaStreamSynchronize(s));
    CK(cudaEventElapsedTime(&ms,a,b));
    printf("H2D pageable: %.2f GiB/s\n", gib/(ms/1000.0));
    return 0;
}
