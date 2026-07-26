// Hook de diagnostico: intercepta PVRSRVGetDevices com cuidado
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>

typedef int (*prop_get_t)(const char*, char*);
typedef long (*getdev_t)(long, long, long, long, long, long);

int __system_property_get(const char *name, char *value) {
    static prop_get_t real = NULL;
    if (!real) real = (prop_get_t) dlsym(RTLD_NEXT, "__system_property_get");
    if (strcmp(name, "ro.build.type") == 0) { strcpy(value, "userdebug"); return 9; }
    if (strcmp(name, "ro.debuggable") == 0) { strcpy(value, "1"); return 1; }
    if (strcmp(name, "vendor.product.pvr.debug_level") == 0) { strcpy(value, "1"); return 1; }
    return real(name, value);
}

long PVRSRVGetDevices(long a0, long a1, long a2, long a3, long a4, long a5) {
    static getdev_t real = NULL;
    if (!real) {
        void *h = dlopen("/data/data/com.termux/files/home/ocl/libsrv_um.so", RTLD_NOW | RTLD_NOLOAD);
        if (!h) h = dlopen("/data/data/com.termux/files/home/ocl/libsrv_um.so", RTLD_NOW);
        if (h) real = (getdev_t) dlsym(h, "PVRSRVGetDevices");
        fprintf(stderr, "[HOOK] real PVRSRVGetDevices = %p\n", (void*)real);
        fflush(stderr);
    }
    if (!real) return -1;
    long r = real(a0, a1, a2, a3, a4, a5);
    fprintf(stderr, "[HOOK] GetDevices ret=%ld count=%d dev0_flags=%08x\n",
            r, a2 ? *(int*)a2 : -999, a0 ? *(unsigned int*)a0 : 0);
    fflush(stderr);
    return r;
}

typedef long (*gpudinit_t)(long, long, long, long);

long gpudInitialize(long a0, long a1, long a2, long a3) {
    static gpudinit_t real = NULL;
    if (!real) {
        void *h = dlopen("/data/data/com.termux/files/home/ocl/libgpud.so", RTLD_NOW | RTLD_NOLOAD);
        if (!h) h = dlopen("/data/data/com.termux/files/home/ocl/libgpud.so", RTLD_NOW);
        if (h) real = (gpudinit_t) dlsym(h, "gpudInitialize");
        fprintf(stderr, "[HOOK] real gpudInitialize = %p\n", (void*)real);
        fflush(stderr);
    }
    if (!real) return -1;
    long r = real(a0, a1, a2, a3);
    fprintf(stderr, "[HOOK] gpudInitialize(type=%ld) ret=%ld\n", a0, r);
    fflush(stderr);
    return r;
}

typedef long (*gr_t)(long, long, long, long);

static void *mapper_handle(void) {
    void *h = dlopen("/data/data/com.termux/files/home/ocl/libpvr_mapper_utils.so", RTLD_NOW | RTLD_NOLOAD);
    if (!h) h = dlopen("/data/data/com.termux/files/home/ocl/libpvr_mapper_utils.so", RTLD_NOW);
    return h;
}

long gr_getMapper(long a0, long a1, long a2, long a3) {
    static gr_t real = NULL;
    if (!real) { void *h = mapper_handle(); if (h) real = (gr_t) dlsym(h, "gr_getMapper"); }
    if (!real) return -1;
    long r = real(a0, a1, a2, a3);
    fprintf(stderr, "[HOOK] gr_getMapper ret=%ld\n", r);
    fflush(stderr);
    return r;
}

long gr_getDevConnection(long a0, long a1, long a2, long a3) {
    static gr_t real = NULL;
    if (!real) { void *h = mapper_handle(); if (h) real = (gr_t) dlsym(h, "gr_getDevConnection"); }
    if (!real) return -1;
    long r = real(a0, a1, a2, a3);
    fprintf(stderr, "[HOOK] gr_getDevConnection ret=%ld\n", r);
    fflush(stderr);
    return r;
}

typedef void *(*sphal2_t)(const char*, int);

void *android_load_sphal_library(const char *name, int flag) {
    fprintf(stderr, "[HOOK] sphal(%s) -> redirecionando p/ namespace local\n", name ? name : "?");
    fflush(stderr);
    if (name && strstr(name, "mapper.powervr")) {
        void *h = dlopen("/data/data/com.termux/files/home/ocl/mapper.powervr.so", RTLD_NOW | RTLD_GLOBAL);
        fprintf(stderr, "[HOOK] dlopen local mapper: %s\n", h ? "OK" : dlerror());
        fflush(stderr);
        return h;
    }
    static sphal2_t real = NULL;
    if (!real) real = (sphal2_t) dlsym(RTLD_NEXT, "android_load_sphal_library");
    return real ? real(name, flag) : NULL;
}
