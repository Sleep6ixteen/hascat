#include <stdio.h>
#include <dlfcn.h>

typedef int (*clp_t)(unsigned, void**, unsigned*);
typedef int (*cld_t)(void*, unsigned long, unsigned, void**, unsigned*);
typedef int (*cldi_t)(void*, unsigned, size_t, void*, size_t*);

#define CL_DEVICE_TYPE_GPU (1UL << 2)
#define CL_DEVICE_TYPE_ALL 0xFFFFFFFFUL

int main(void) {
    dlopen("/data/data/com.termux/files/home/ocl/libPVROCL.so", RTLD_NOW | RTLD_GLOBAL);
    void *h = dlopen("/data/data/com.termux/files/usr/lib/libOpenCL.so", RTLD_NOW | RTLD_GLOBAL);
    if (!h) { printf("FALHOU loader: %s\n", dlerror()); return 1; }
    clp_t gp = (clp_t) dlsym(h, "clGetPlatformIDs");
    cld_t gd = (cld_t) dlsym(h, "clGetDeviceIDs");
    cldi_t gdi = (cldi_t) dlsym(h, "clGetDeviceInfo");

    void *plats[4]; unsigned np = 0;
    int r = gp(4, plats, &np);
    printf("plataformas: %d (ret=%d)\n", np, r);

    char buf[256]; size_t sz;
    gp(0,0,0);
    typedef int (*gpi_t)(void*, unsigned, size_t, void*, size_t*);
    gpi_t gpi = (gpi_t) dlsym(h, "clGetPlatformInfo");
    if (np && gpi) {
        gpi(plats[0], 0x0902, sizeof buf, buf, &sz); printf("nome: %s\n", buf);
        gpi(plats[0], 0x0903, sizeof buf, buf, &sz); printf("vendor: %s\n", buf);
        gpi(plats[0], 0x0904, sizeof buf, buf, &sz); printf("versao: %s\n", buf);
    }

    void *devs[8]; unsigned nd = 0;
    r = gd(plats[0], CL_DEVICE_TYPE_ALL, 8, devs, &nd);
    printf("devices: %d (ret=%d)\n", nd, r);
    for (unsigned i = 0; i < nd; i++) {
        gdi(devs[i], 0x4080, sizeof buf, buf, &sz); printf("device #%u nome: %s\n", i, buf);
        gdi(devs[i], 0x4094, sizeof buf, buf, &sz); printf("  versao CL: %s\n", buf);
        unsigned long v;
        gdi(devs[i], 0x1002, sizeof v, &v, 0); printf("  compute units: %lu\n", v);
        gdi(devs[i], 0x1004, sizeof v, &v, 0); printf("  clock max: %lu MHz\n", v);
        gdi(devs[i], 0x101F, sizeof v, &v, 0); printf("  global mem: %lu MB\n", v/1048576);
        gdi(devs[i], 0x1023, sizeof v, &v, 0); printf("  local mem: %lu bytes\n", v);
        gdi(devs[i], 0x1005, sizeof v, &v, 0); printf("  max workgroup: %lu\n", v);
    }
    return 0;
}
