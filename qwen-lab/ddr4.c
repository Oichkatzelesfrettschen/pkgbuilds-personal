/* Sustained DDR4 read bandwidth, measured the same way bench/h2d.cu measures PCIe.
 *
 * The C arm computes host-resident layers on the CPU instead of shipping them
 * over PCIe, so its per-token cost is set by how fast DDR4 delivers those
 * weights rather than by the 24.06 GiB/s bus. That number needs the same
 * treatment the bus got: measured on this machine, not quoted from a spec
 * sheet, because the JEDEC peak assumes both channels streaming with no
 * refresh, no other traffic, and a compositor that is not running.
 *
 * The AMD data-fabric PMU on family 19h model 21h exposes no die-to-DRAM event
 * this kernel's tables can name, so a counter reading is unavailable and a
 * raw-encoded guess would not be checkable. A read-only streaming sum over a
 * buffer several times the 32 MiB L3 is checkable: every byte comes from DRAM,
 * and the compiler cannot elide the sum because it is returned.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <omp.h>

static double now(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;
}

int main(int argc, char **argv)
{
    /* 2 GiB is 64x the 32 MiB V-Cache, so L3 residency cannot flatter the read. */
    size_t bytes = (argc > 1) ? (size_t)atof(argv[1]) * (1UL << 30) : (2UL << 30);
    int iters = (argc > 2) ? atoi(argv[2]) : 8;
    int max_threads = (argc > 3) ? atoi(argv[3]) : 12;

    size_t n = bytes / sizeof(double);
    double *a = aligned_alloc(4096, n * sizeof(double));
    if (!a) { fprintf(stderr, "alloc failed\n"); return 1; }

    /* First touch populates the pages; an untouched mapping would measure the
     * page fault path rather than DRAM. */
    for (size_t i = 0; i < n; i++) a[i] = (double)i;

    printf("buffer %.2f GiB, %d iterations\n", bytes / 1073741824.0, iters);
    printf("threads   GiB/s\n");

    for (int t = 1; t <= max_threads; t <<= 1) {
        if (t > max_threads) break;
        omp_set_num_threads(t);
        double best = 0.0;
        for (int k = 0; k < iters; k++) {
            double sum = 0.0;
            double t0 = now();
            #pragma omp parallel for reduction(+:sum) schedule(static)
            for (size_t i = 0; i < n; i++) sum += a[i];
            double dt = now() - t0;
            double gibs = (bytes / 1073741824.0) / dt;
            if (gibs > best) best = gibs;
            if (sum == 12345.6789) printf("");  /* defeat elision */
        }
        printf("%7d   %6.2f\n", t, best);
    }

    /* The two counts that matter for this host: six physical cores and twelve
     * logical, matching the llama.cpp thread sweep. */
    for (int t = 6; t <= 12; t += 6) {
        omp_set_num_threads(t);
        double best = 0.0;
        for (int k = 0; k < iters; k++) {
            double sum = 0.0;
            double t0 = now();
            #pragma omp parallel for reduction(+:sum) schedule(static)
            for (size_t i = 0; i < n; i++) sum += a[i];
            double dt = now() - t0;
            double gibs = (bytes / 1073741824.0) / dt;
            if (gibs > best) best = gibs;
            if (sum == 12345.6789) printf("");
        }
        printf("%7d   %6.2f\n", t, best);
    }

    free(a);
    return 0;
}
